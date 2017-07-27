-- ---------------------------------------------------------------------------
--
-- VNC server application with u8g2 rendering
--
-- You need to compile the firmware with u8g2 module and enabled display
-- driver ssd1306_128x64_noname.
--
-- Also see http://nodemcu.readthedocs.io/en/dev-esp32/en/modules/u8g2/
--
-- ---------------------------------------------------------------------------

srv_width  = 128
srv_height =  64

-- precalculated white color
white = -1

vncsrv = require("vncserver")


-- ***************************************************************************
-- Callback function for the u8g driver.
--
-- It gets a framebuffer line in rle encoding and transforms this into
-- an RRE rectangle for the client.
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
-- u8g2 related
--
-- Draw moving triangles
--
function triangle(ds)
  local offset = bit.band(ds, 7)
  disp:drawStr(0, 0, "drawTriangle")
  disp:drawTriangle(14,7, 45,30, 10,40)
  disp:drawTriangle(14+offset,7-offset, 45+offset,30-offset, 57+offset,10-offset)
  disp:drawTriangle(57+offset*2,10, 45+offset*2,30, 86+offset*2,53)
  disp:drawTriangle(10+offset,40+offset, 45+offset,30+offset, 86+offset,53+offset)
end
--
-- u8g2's drawing mechanics.
--
function draw_loop()
  -- only start a new display if white color is precalculated
  if white > 0 then
    -- speed up frame rendering
    node.egc.setmode(node.egc.ON_ALLOC_FAILURE)

    disp:clearBuffer()
    triangle(draw_state)
    disp:sendBuffer()
  
    -- increase the state
    draw_state = draw_state + 1
    if draw_state >= 12*8 then
      draw_state = 0
    end

    node.egc.setmode(node.egc.ALWAYS)
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
  draw_state = 0
  -- unregister data sent callback
  vncsrv.on( "data_sent" )
end


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
draw_state = 0

-- Configure VNC server
vncsrv.on( "disconnection", cb_disconnect )
vncsrv.on( "fb_update", function ()
             if white < 0 then
               -- first update request: precalculate white color
               white = bit.bor( bit.lshift( vncsrv.red_max, vncsrv.red_shift ),
                                bit.lshift( vncsrv.green_max, vncsrv.green_shift ),
                                bit.lshift( vncsrv.blue_max, vncsrv.blue_shift ) )

               -- start drawing with the first FramebufferUpdateRequest
               -- this example will loop only once
               vncsrv.on( "data_sent", draw_loop )
               node.task.post( draw_loop )
             end
end)


-- Set up TCP server
srv = net.createServer( net.TCP, 120 )
srv:listen( 5900,
            function( conn )
              -- start VNC server with connected socket
              vncsrv.start( conn, srv_width, srv_height )
            end
)
