-- ---------------------------------------------------------------------------
--
-- VNC server application input demo
--
-- ---------------------------------------------------------------------------

require("vncserver").createServer(5900, 128, 64,
  function( srv )
    local bit = bit
    local id = "myhandler"

    -- Process key events
    srv.cb_key = function( srv, key, down )
      local action
      if down then
        action = "pressed"
      else
        action = "released"
      end
      if key >= 10 and key <= 127 then
        print( ("key '%c' %s"):format( key, action ) )
      else
        print( ("key '0x%04x' %s"):format( key, action ) )
      end
    end

    -- Process pointer events
    srv.cb_pointer = function( srv, button_mask, x, y )
      local buttons = ""

      print( ("pointer at x %d / y %d"):format( x, y ) )

      if bit.band( button_mask, 2^0 ) > 0 then
        buttons = "left "
      end
      if bit.band( button_mask, 2^1 ) > 0 then
        buttons = buttons.."middle "
      end
      if bit.band( button_mask, 2^2 ) > 0 then
        buttons = buttons.."right "
      end
      if bit.band( button_mask, 2^3 ) > 0 then
        buttons = buttons.."up "
      end
      if bit.band( button_mask, 2^4 ) > 0 then
        buttons = buttons.."down "
      end
      if bit.band( button_mask, 2^5 ) > 0 then
        buttons = buttons.."left "
      end
      if bit.band( button_mask, 2^6 ) > 0 then
        buttons = buttons.."right"
      end
      if buttons:len() > 0 then
        print( ("button: %s"):format( buttons ) )
      end
    end

    srv.cb_disconnection = function( srv )
      print( id, "disconnection event" )
    end

  end
)
