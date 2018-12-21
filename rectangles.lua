-- ---------------------------------------------------------------------------
--
-- VNC server application raw rectangles demo
--
-- ---------------------------------------------------------------------------

require("vncserver").createServer(5900, 128, 128,
  function( srv )
    local bit = bit
    local id = "myhandler"
    local red, green, blue, yellow
    print("handler started")

    local function init()
      red, green, blue, yellow = 0, 0, 0, 0
    end

    -- callbacks for sever
    srv.cb_fbupdate = function( srv )
      --print(id, "frame buffer update requested")

      if red == 0 then
        -- compute rgb colors during first run
        red = bit.lshift( srv.red_max, srv.red_shift )
        green = bit.lshift( srv.green_max, srv.green_shift )
        blue = bit.lshift( srv.blue_max, srv.blue_shift )
        yellow = bit.bor( red, green )
      end

      srv:update_fb( 1 )   -- 1 rectangle follows
      srv:rre_rectangle( 0, 0, 128, 128, 4, 0 )   -- 4 sub-rectangles follow

      srv:rre_subrectangle( 10, 10, 30, 10, red )
      srv:rre_subrectangle( 50, 20, 20, 40, green )
      srv:rre_subrectangle( 80, 80, 40, 40, blue )
      srv:rre_subrectangle( 60, 50, 30, 50, yellow )

    end

    srv.cb_disconnection = function( srv )
      print(id, "disconnection event")
      init()
    end

    init()
  end
)
