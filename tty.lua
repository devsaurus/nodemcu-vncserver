-- ---------------------------------------------------------------------------
--
-- VNC server application tty responder
--
-- You need to compile the firmware with u8g2 module.
-- Also see http://nodemcu.readthedocs.io/en/master/en/build/
--
-- ---------------------------------------------------------------------------

local srv_width  = 128
local srv_height =  64

-- precalculated white color
local white = -1

local textbuffer = {""}

-- cache ROM modules
local struct, bit, node = struct, bit, node

-- ***************************************************************************
-- Callback function for the u8g2 driver.
--
-- It gets a framebuffer line in rle encoding and transforms this into
-- an RRE rectangle for the client.
--
function drv_cb( data )
  if data == nil then
    -- start new FramebufferUpdate
    cb_line = 0
    -- we're going to send the full framebuffer with this update
    vncsrv:update_fb( srv_height )

  else
    -- send a line aka rectangle
    local num_subrects = struct.unpack( "B", data )
    vncsrv:rre_rectangle( 0, cb_line, srv_width, 1, num_subrects, 0 )

    for i = 0, num_subrects-1 do
      local x, len = struct.unpack( "BB", data, 2 + i*2 )
      vncsrv:rre_subrectangle( x, 0, len, 1, white )
    end

    cb_line = cb_line + 1

  end
end


-- ***************************************************************************
-- u8g2 related
--
-- Draw text
--
function draw_text()
  for line = 1,#textbuffer do
    disp:drawStr( 0, (line-1) * 10, textbuffer[line] )
  end
end
--
-- u8g2's drawing mechanics.
--
function draw()
  -- only start a new display if white color is precalculated
  if white > 0 then
    -- speed up frame rendering
    node.egc.setmode(node.egc.ON_ALLOC_FAILURE)

    disp:clearBuffer()
    draw_text()
    disp:sendBuffer()

    node.egc.setmode(node.egc.ALWAYS)
  end
end



-- ***************************************************************************
-- The server instance
--
require("vncserver").createServer(5900, srv_width, srv_height,
  function( srv )
    local bit = bit
    local id = "myhandler"
    vncsrv = srv

    print("handler started")

    srv.cb_disconnection = function( srv )
      print( id, "disconnection event" )
      -- disable draw loop
      white = -1
      textbuffer = {""}
      -- unregister vnc server
      vncsrv = nil
    end

    srv.cb_key = function( srv, key, down )
      if down then
        if key < 32 or key > 127 then return end

        local linenum = #textbuffer

        if #textbuffer[linenum] < srv_width/6 then
          textbuffer[linenum] = ("%s%c"):format( textbuffer[linenum], key )
        else
          -- prepare next line
          if linenum == srv_height/10 then
            table.remove( textbuffer, 1 )
            textbuffer[linenum] = key:char()
          else
            textbuffer[linenum + 1] = key:char()
          end
        end

        node.task.post( draw )
      end
    end

    srv.cb_fbupdate = function( srv )
      if white < 0 then
        -- first update request: precalculate white color
        white = bit.bor( bit.lshift( srv.red_max, srv.red_shift ),
                         bit.lshift( srv.green_max, srv.green_shift ),
                         bit.lshift( srv.blue_max, srv.blue_shift ) )
      end
    end

  end
)


-- ***************************************************************************
-- Initialization part
--

-- Init u8g2:
-- virtual u8g2 display, delivers framebufer lines in rle encoding
disp = u8g2.ssd1306_128x64_noname( drv_cb )
disp:setFont( u8g2.font_6x10_tf )
disp:setFontRefHeightExtendedText()
disp:setDrawColor( 1 )
disp:setFontPosTop()
disp:setFontDirection( 0 )
