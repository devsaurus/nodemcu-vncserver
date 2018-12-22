-- ***************************************************************************
-- VNC server framework for Lua on NodeMCU.
--
-- An implementaion of the RFB protocol:
--    http://vncdotool.readthedocs.io/en/latest/rfbproto.html
--
-- Inspired by pylotron, https://github.com/cnlohr/pylotron
--
-- ---------------------------------------------------------------------------
--
-- Copyright (c) 2016-2018, Arnim Laeuger
--
-- Redistribution and use in source, with or without modification, are
-- permitted provided the above copyright notice and these terms are retained.
--
-- ---------------------------------------------------------------------------
--

local module = ...
package.loaded[module] = nil


local struct, bit, table = struct, bit, table
local vncserver

do

  -- *************************************************************************
  --
  -- buffer object
  --
  -- methods
  local function buffer_sent( self )
    if #self.buffer > 0 then
      self.conn:send( table.remove( self.buffer, 1 ) )
    else
      self.buffer = nil
      self.conn:on( "sent", nil )
      if self.cb_sent and not self.lock_buffer then self.cb_sent() end
    end
  end
  --
  local function buffer_int_queue( self, data )
    if self.conn == nil then return end

    if self.buffer == nil then
      self.buffer = {}
      self.conn:on( "sent", function() self:sent() end )
      self.conn:send( data )
    else
      local len = #self.buffer
      if len > 0 and (data:len() + self.buffer[len]:len()) < 1400 then
        -- marshall small data strings
        self.buffer[len] = self.buffer[len] .. data
      else
        -- add payload to buffer
        self.buffer[len + 1] = data
      end

    end
  end
  --
  local function buffer_queue( self, data )
    if self.lock_buffer then
      error( "buffer is locked by server" )
    else
      self:_queue( data )
    end
  end
  --
  -- functions
  --
  local function make_buffer( conn, cb_sent )
    local buf = {
      conn = conn,
      buffer = nil,
      lock_buffer = true,
      cb_sent = cb_sent
    }
    buf._queue = buffer_int_queue
    buf.queue = buffer_queue
    buf.sent = buffer_sent

    -- explicit function, we can't set a metatable with __gc() for Lua 5.1
    buf.dispose = function( self )
      -- ensure that callback is unref'ed when buffer is disposed
      self.conn:on( "sent", nil )
    end

    return buf
  end
  --
  -- *************************************************************************


  -- *************************************************************************
  --
  -- server object
  --
  -- methods
  --
  -- rre_rectangle( x, y, w, h, num_subrects, bg )
  -- Starts a rectangle in RRE format composed out of 'num_subrects' sub-rectangles.
  local function rre_rectangle( srv, x, y, w, h, num_subrects, bg )
    srv.buf:queue( struct.pack( ">I2I2I2I2i4I4"..srv.bpp_format, x, y, w, h, 2,
                                num_subrects, bg ) )
  end
  --
  -- rre_subrectangle( x, y, w, h, fg )
  -- Append an RRE subrectangle to a previously started rectangle.
  local function rre_subrectangle( srv, x, y, w, h, fg )
    srv.buf:queue( struct.pack( srv.bpp_format..">I2I2I2I2", fg, x, y, w, h ) )
  end
  --
  -- update_fb( num_rects )
  -- Start a framebuffer update consisting of 'num_rects' rectangles to follow.
  local function update_fb( srv, num_rects )
    srv.buf:queue( struct.pack( ">BBI2", 0, 0, num_rects ) )
  end
  --
  -- functions
  --
  local function srv_buf_sent( srv )
    if srv.cb_datasent then srv:cb_datasent() end
  end

  local function msg( message )
    if true then
      print( message )
    end
  end

  local function num_bits_used( val )
    local num = 0
    while val > 0 do
      num = num + 1
      val = bit.rshift( val, 1 )
    end
    return num
  end

  local function make_srv( conn, width, height )
    local srv = {
      width = width,
      height = height,

      bpp_format = nil,

      red_max = 0,
      red_shift = 0,
      red_len = 0,

      green_max = 0,
      green_shift = 0,
      green_len = 0,

      blue_max = 0,
      blue_shift = 0,
      blue_len = 0,
    }

    srv.rre_rectangle = rre_rectangle
    srv.rre_subrectangle = rre_subrectangle
    srv.update_fb = update_fb

    srv.buf = make_buffer( conn, function() srv_buf_sent( srv ) end )

    return srv
  end
  --
  -- *************************************************************************


  local function vnc_handler( handler, width, height )
    return function( conn )
      local srv = make_srv( conn, width, height )
      local srv_state = "connected"

      local function ondisconnected( conn )
        print("disconnected")
        if srv.cb_disconnection then srv:cb_disconnection() end
        srv.buf:dispose()
        srv = nil
      end

      local function onreceive( conn, data )
        if srv_state == "connected" then
          -- server announces its protocol version
          srv.buf:_queue( "RFB 003.003\n" )
          srv_state = "wait_clientproto"
          msg( srv_state )

        elseif srv_state == "wait_clientproto" then
          -- client selects protocol version
          -- just omit data

          -- send security handshake
          -- no security
          srv.buf:_queue( struct.pack( ">I4", 1 ) )
          srv_state = "wait_clientinit"
          msg( srv_state )

        elseif srv_state == "wait_clientinit" then
          -- get sharing info
          -- just omit data

          -- send server init
          srv.buf:_queue( struct.pack( ">I2I2BBBBI2I2I2BBBbbbI4s", srv.width, srv.height, 8, 3, 0, 1, 1, 1, 1, 0, 1, 2, 0, 0, 0, 4, "ESP" ) )
          srv_state = "wait_clientmsg"
          msg( srv_state )

        elseif srv_state == "wait_clientmsg" then
          local offset = 1
          -- loop through received data
          while offset < #data do
            local cmd = struct.unpack( "B", data, offset )
            offset = offset + 1

            if cmd == 0 then
              -- client requests different pixel type

              local bpp, dep, be, tc = struct.unpack( "BBBB", data, offset + 3 )
              offset = offset + 3+4
              srv.red_max, srv.green_max, srv.blue_max, srv.red_shift, srv.green_shift, srv.blue_shift = struct.unpack( ">I2I2I2BBB", data, offset )
              offset = offset + 9+3
              -- determine how many bits are used for the color components
              srv.red_len = num_bits_used( srv.red_max )
              srv.green_len = num_bits_used( srv.green_max )
              srv.blue_len = num_bits_used( srv.blue_max )

              srv.white = bit.bor( bit.lshift( srv.red_max, srv.red_shift),
                                   bit.lshift( srv.green_max, srv.green_shift),
                                   bit.lshift( srv.blue_max, srv.blue_shift) )

              local endian_format
              if be > 0 then
                endian_format = ">"
              else
                endian_format = "<"
              end
              if bpp == 8 then
                srv.bpp_format = "B"
              elseif bpp == 16 then
                srv.bpp_format = endian_format.."I2"
              elseif bpp == 24 or bpp == 32 then
                srv.bpp_format = endian_format.."I4"
              end

            elseif cmd == 2 then
              -- encodings
              local num_encodings = struct.unpack( ">I2", data, offset + 1 )
              offset = offset + 1 + num_encodings*4

            elseif cmd == 3 then
              -- client requests update
              offset = offset + 9
              srv.buf.lock_buffer = false
              if srv.cb_fbupdate then srv:cb_fbupdate() end

            elseif cmd == 4 then
              -- key press event
              if srv.cb_key then
                local down, _, key = struct.unpack( ">BI2I4", data, offset )
                srv:cb_key( key, down > 0 )
              end
              offset = offset + 7

            elseif cmd == 5 then
              -- pointer event
              if srv.cb_pointer then
                srv:cb_pointer( struct.unpack( ">BI2I2", data, offset ) )
              end
              offset = offset + 5

            elseif cmd == 6 then
              -- client cut text

            end

          end  -- while
        end
      end

      conn:on( "disconnection", ondisconnected )
      conn:on( "receive", onreceive )

      handler( srv )

      onreceive( conn, nil )
    end
  end

  local srv
  local function createServer( port, width, height, handler )
    -- NB: only one server at a time
    if srv then srv:close() end
    srv = net.createServer( net.TCP, 120 )
    -- listen
    srv:listen( port, vnc_handler( handler, width, height ) )
    return srv
  end


  vncserver = {
    createServer = createServer
  }
end

return vncserver
