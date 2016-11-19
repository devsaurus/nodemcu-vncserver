-- ---------------------------------------------------------------------------
--
-- VNC server application tty responder
--
-- This example uses the virtual 'fb_rle' display which is available in
-- dev https://github.com/nodemcu/nodemcu-firmware/tree/dev
--
-- You need to compile the firmware with u8g module and enabled fbrle display
-- in u8g_config.h:
--   #define U8G_DISPLAY_FB_RLE
--
-- ---------------------------------------------------------------------------

srv_width  = 128
srv_height =  64

-- precalculated white color
white = -1

textbuffer = {}
textbuffer[1] = ""
draw_busy = false
pending_draw = false

vncsrv = require("vncserver")

-- ***************************************************************************
-- Callback function for the u8g driver.
--
function drv_cb( data )
  if data == nil then
    -- start new FramebufferUpdate
    cb_line = 0
    -- we're going to send the full framebuffer with this update
    vncsrv.update_fb( srv_height )

  else
    -- send a line aka rectangle
    local num_subrects = struct.unpack( "B", data )
    vncsrv.rre_rectangle( 0, cb_line, srv_width, 1, num_subrects, 0 )

    for i = 0, num_subrects-1 do
      local x, len = struct.unpack( "BB", data, 2 + i*2 )
      vncsrv.rre_subrectangle( x, 0, len, 1, white )
    end

    cb_line = cb_line + 1

  end
end


-- ***************************************************************************
-- U8glib related
--
-- Draw moving triangles
--
function draw_text()
  for line = 1,#textbuffer do
    disp:drawStr( 0, (line-1) * 10, textbuffer[line] )
  end
end
--
-- U8glib's drawing mechanics.
--
function draw_loop()
  local function drawPages()
    if white <= 0 then return end

    draw_text()
    if disp:nextPage() == true then
      -- do nothing, the data which was queued during nextPage() will execute
      -- drawPages() as data_sent callback once all data is at the client
    else
      vncsrv.on( "data_sent" )
      draw_busy = false
      if pending_draw then
        node.task.post( draw_loop )
      end
      -- fall back to standard strategy to allow for full gc
      node.egc.setmode(node.egc.ALWAYS)
    end
  end

  if draw_busy then
    pending_draw = true
    return
  end

  -- only start a new display if white color is precalculated
  if white > 0 then
    draw_busy = true
    pending_draw = false

    -- speed up frame rendering
    node.egc.setmode(node.egc.ON_ALLOC_FAILURE)
    disp:firstPage()
    vncsrv.on( "data_sent", drawPages )
  end
end


-- ***************************************************************************
-- VNC client message callbacks
-- 
-- Stop drawing loop upon disconnect.
--
function cb_disconnect()
  print( "client disconnected" )
  -- disable draw loop
  white = -1
  -- unregister data sent callback
  vncsrv.on( "data_sent" )

  textbuffer = {}
  textbuffer[1] = ""
end

function cb_key( key, down )
  if down then
    if key < 32 or key > 127 then return end

    local linenum = #textbuffer

    if #textbuffer[linenum] < srv_width/6 then
      textbuffer[linenum] = string.format( "%s%c", textbuffer[linenum], key )
    else
      -- prepare next line
      if linenum == srv_height/10 then
        table.remove( textbuffer, 1 )
        textbuffer[linenum] = string.char( key )
      else
        textbuffer[linenum + 1] = string.char( key )
      end
    end

    draw_loop()
  end
end


-- ***************************************************************************
-- Initialization part
--

-- Init u8glib:
-- virtual u8g display, delivers framebufer lines in rle encoding
disp = u8g.fb_rle( drv_cb, srv_width, srv_height )
disp:setFont(u8g.font_6x10)
disp:setFontRefHeightExtendedText()
disp:setDefaultForegroundColor()
disp:setFontPosTop()

-- Configure VNC server
vncsrv.on( "disconnection", cb_disconnect )
vncsrv.on( "fb_update", function ()
             if white < 0 then
               -- first update request: precalculate white color
               white = bit.bor( bit.lshift( vncsrv.red_max, vncsrv.red_shift ),
                                bit.lshift( vncsrv.green_max, vncsrv.green_shift ),
                                bit.lshift( vncsrv.blue_max, vncsrv.blue_shift ) )
             end
end)
vncsrv.on( "key", cb_key )

-- Set up TCP server
srv = net.createServer( net.TCP, 120 )
srv:listen( 5900,
            function( conn )
              -- start VNC server with connected socket
              vncsrv.start( conn, srv_width, srv_height )
            end
)
