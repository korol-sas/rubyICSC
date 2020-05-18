require "../icsc"
# fuser -av /dev/ttyUSB*
icsc = ICSC.new('/dev/ttyUSB0', 115200, 'C')

# Broadcast to all for disable
icsc.broadcast('D')
sleep(1)

icsc.add_command('T') do |message|
  puts "receiverd data: #{message[:data]} on T command"
end

icsc.process
#
# while true do
#   icsc.send('B', 'E')
#   sleep(1)
#   icsc.send('B', 'D')
#   sleep(1)
# end
