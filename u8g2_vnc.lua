-- ---------------------------------------------------------------------------
--
-- VNC server application triangle graphics demo
--
-- You need to compile the firmware with u8g2 module.
-- Also see http://nodemcu.readthedocs.io/en/master/en/build/
--
-- ---------------------------------------------------------------------------

local srv_width  = 128
local srv_height =  64

-- precalculated white color
local white = -1

local vncsrv = nil
local disp = nil
local draw_state = 0
local cb_line = 0

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
function draw()
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
-- The server instance
--
require("vncserver").createServer(5900, srv_width, srv_height,
  function( srv )
    local bit = bit
    local id = "myhandler"
    vncsrv = srv

    print("handler started")

    srv.cb_datasent = function( srv )
      node.task.post( draw )
    end

    srv.cb_disconnection = function( srv )
      print( id, "disconnection event" )
      -- disable draw loop
      white = -1
      draw_state = 0
      -- unregister data sent callback
      srv.cb_datasent = nil
      -- unregister vnc server
      vncsrv = nil
    end

    srv.cb_fbupdate = function( srv )
      if white < 0 then
        -- first update request: precalculate white color
        white = bit.bor( bit.lshift( srv.red_max, srv.red_shift ),
                         bit.lshift( srv.green_max, srv.green_shift ),
                         bit.lshift( srv.blue_max, srv.blue_shift ) )

        -- start drawing with the first FramebufferUpdateRequest
        -- this example will loop only once
        node.task.post( draw )
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
