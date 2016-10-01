
vncsrv = require("vncserver")

-- precalculated colors
red = 0
green = 0
blue = 0
yellow = 0

-- ***************************************************************************
-- VNC client message callbacks
-- 
function cb_disconnect()
  print( "client disconnected" )
end

function draw_rectangles()
  if red == 0 then
    -- compute rgb colors during first run
    red = bit.lshift( vncsrv.red_max, vncsrv.red_shift )
    green = bit.lshift( vncsrv.green_max, vncsrv.green_shift )
    blue = bit.lshift( vncsrv.blue_max, vncsrv.blue_shift )
    yellow = bit.bor( red, green )
  end

  vncsrv.update_fb( 1 )   -- 1 rectangle follows
  vncsrv.rre_rectangle( 0, 0, 128, 128, 4, 0 )   -- 4 sub-rectangles follow

  vncsrv.rre_subrectangle( 10, 10, 30, 10, red )
  vncsrv.rre_subrectangle( 50, 20, 20, 40, green )
  vncsrv.rre_subrectangle( 80, 80, 40, 40, blue )
  vncsrv.rre_subrectangle( 60, 50, 30, 50, yellow )
end


-- Configure VNC server
vncsrv.on( "disconnection", cb_disconnect )
vncsrv.on( "fb_update", draw_rectangles )

-- Set up TCP server
srv = net.createServer( net.TCP, 120 )
srv:listen( 5900,
            function( conn )
              -- start VNC server with connected socket
              vncsrv.start( conn, 128, 128 )
            end
)
