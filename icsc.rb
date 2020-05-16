#!/usr/bin/ruby
require "rubygems"
require "serialport"

class ICSC
  SOH = 1
  STX = 2
  ETX = 3
  EOT = 4

  attr_accessor :serial, :config, :station

  def initialize(port, baud, station, config = {})
    @config = config
    @serial = SerialPort.new(port, baud, 8, 1, SerialPort::NONE)

    @station = station.is_a?(String) ? station[0].ord : station
  end

  def send(dest_station, cmd, data)
    dest_station = dest_station.is_a?(String) ? dest_station[0].ord : dest_station
    cmd = cmd.is_a?(String) ? cmd[0].ord : cmd
    data = data.is_a?(String) ? data.bytes.to_a : [data]

    packet = [
      SOH,
      dest_station,
      @station,
      cmd,
      data.length,
      STX,
      *data,
      ETX,
      calculate_checksum([dest_station, @station, cmd, data.length], data),
      EOT
    ]

    packet = packet.map { |byte| byte.chr }.join

    @serial.write(packet)
  end

  private

  def calculate_checksum(header, data)
    (header.sum + data.sum) % 256
  end

end

icsc = ICSC.new('/dev/ttyUSB1', 115200, 'C')
icsc.send('B', 'D', 'data')
