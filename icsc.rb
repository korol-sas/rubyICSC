#!/usr/bin/ruby
require 'rubygems'
require 'serialport'
require 'timeout'

class ICSC
  class FlowError
    NO_ERROR = 0
    BAD_FORMAT = 1
    VOID_MSG = 2
    TO_SHORT_MSG = 3

    # Logical errors
    UNEXPECTED_ORIGIN = 3
    UNEXPECTED_CMD = 4
    WRONG_DEST_STATION = 5

    # Meta data fields errors
    BAD_LEN_FIELD = 6
    BAD_CHECKSUM = 7

    # Control fields errors
    MISSING_SOH = 8
    MISSING_STX = 9
    MISSING_ETX = 10
    MISSING_EOT = 11

    # Flow errors
    TIMEOUT = 12
    MANY_RETRIES = 13
  end

  SOH = 1
  STX = 2
  ETX = 3
  EOT = 4
  ENQ = 5
  ACK = 6
  NUL = 0

  ICSC_SYS_PING = ENQ
  ICSC_SYS_PONG = ACK
  ICSC_BROADCAST = NUL

  SOH_IDX = 0
  DEST_ID_IDX = 1
  ORIG_ID_IDX = 2
  CMD_IDX = 3
  DAT_LEN_IDX = 4
  STX_IDX = 5

  PROCESS_TIMEOUT = 1
  MAX_RECEIVE_FAIL = 1
  MIN_MSG_LEN = 9

  attr_accessor :serial, :config, :station, :command_callbacks

  def initialize(port, baud, station, config = {})
    @command_callbacks = {}
    @config = config
    @serial = SerialPort.new(port, baud, 8, 1, SerialPort::NONE)

    @station = station.is_a?(String) ? station[0].ord : station
    @command_callbacks[ICSC_SYS_PING] = -> (message) { respond_to_ping(message) }
  end

  def send(dest_station, command, data = [])
    dest_station = dest_station.is_a?(String) ? dest_station[0].ord : dest_station
    command = command.is_a?(String) ? command[0].ord : command
    data = data.is_a?(String) ? data.bytes.to_a : data

    packet = [
      SOH,
      dest_station,
      @station,
      command,
      data.length,
      STX,
      *data,
      ETX,
      calculate_checksum([dest_station, @station, command, data.length], data),
      EOT
    ]

    packet = packet.map { |byte| byte.chr }.join

    @serial.write(packet)
  end

  def broadcast(command, data = [])
    send(ICSC_BROADCAST, command, data)
  end

  def add_command(command, &block)
    command = command.is_a?(String) ? command[0].ord : command

    @command_callbacks[command] = block
  end

  def process
    # develop_droadcast = true
    while true do
      in_data = read_from_serial

      # if in_data.empty? && develop_droadcast
      #   develop_droadcast = false
      #   broadcast('T', [1,3,5])
      #   next
      # end

      next if in_data.empty?

      error, message = get_message(in_data)

      if error == FlowError::NO_ERROR
        puts "MESSAGE: #{message.inspect}"

        @command_callbacks[message[:cmd].ord].call(message) if @command_callbacks.keys.include?(message[:cmd].ord)
      else
        puts "ERROR: #{error.inspect}"
      end
    end
  end

  private

  def is_truncated_msg(in_data, error)
    in_data[-1] == EOT && [FlowError::BAD_LEN_FIELD, FlowError::TO_SHORT_MSG].include?(error)
  end

  def validate_fields(data, etx_idx, eot_idx)
    return FlowError::MISSING_SOH unless data[SOH_IDX] == SOH
    return FlowError::MISSING_STX unless data[STX_IDX] == STX
    return FlowError::MISSING_ETX unless data[etx_idx] == ETX
    return FlowError::MISSING_EOT unless data[eot_idx] == EOT

    FlowError::NO_ERROR
  end

  def extract_fields(data)
    length = data.length

    return [FlowError::TO_SHORT_MSG, {}] if length < MIN_MSG_LEN
    return [FlowError::BAD_LEN_FIELD, {}] if length != (MIN_MSG_LEN + data[DAT_LEN_IDX])
    return [FlowError::WRONG_DEST_STATION, {}] if data[DEST_ID_IDX] != @station && data[DEST_ID_IDX] != ICSC_BROADCAST

    etx_idx = data[DAT_LEN_IDX].to_i + STX_IDX + 1
    eot_idx = etx_idx + 2

    field_error = validate_fields(data, etx_idx, eot_idx)

    return [field_error, {}] unless field_error == FlowError::NO_ERROR

    payload = data[STX_IDX + 1 .. -4] # STX -> ETX
    checksum_idx = length - 2
    header = [data[DEST_ID_IDX], data[ORIG_ID_IDX], data[CMD_IDX], data[DAT_LEN_IDX]]

    return [FlowError::BAD_CHECKSUM, {}] unless calculate_checksum(header, payload) == data[checksum_idx]

    [FlowError::NO_ERROR, {
      dest_id: data[DEST_ID_IDX].chr,
      orig_id: data[ORIG_ID_IDX].chr,
      cmd: data[CMD_IDX].chr,
      dat_len: data[DAT_LEN_IDX],
      data: payload.map { |byte| byte.chr }.join
    }]
  end

  def get_message(in_data)
    error, message = extract_fields(in_data)

    while is_truncated_msg(in_data, error)
      remaining = read_from_serial
      in_data += remaining

      error, message = extract_fields(in_data)

      break if error == FlowError::NO_ERROR || remaining.length.zero?
    end

    [error, message]
  end

  def read_from_serial
    bytes = []

    Timeout::timeout(PROCESS_TIMEOUT) do
      loop do
        begin
          byte = @serial.readbyte
          bytes << byte

          break if byte == EOT
        rescue EOFError
          break if bytes.empty?
        end
      end
    end

    bytes
  rescue Timeout::Error
    bytes
  end

  def calculate_checksum(header, data)
    data_sum = 0
    data_sum = data.sum unless data.empty?

    (header.sum + data_sum) % 256
  end

  def respond_to_ping(message)
    send(message['orig_id'], ICSC_SYS_PONG, [])
  end
end
