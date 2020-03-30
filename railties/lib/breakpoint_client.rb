require 'breakpoint'
require 'optparse'

options = {
  :ClientURI  => nil,
  :ServerURI  => "druby://localhost:42531",
  :RetryDelay => 10
}

ARGV.options do |opts|
  script_name = File.basename($0)
  opts.banner = [
    "Usage: ruby #{script_name} [options] [server uri]",
    "",
    "This tool lets you connect to a breakpoint service ",
    "which was started via Breakpoint.activate_drb.",
    "",
    "The server uri defaults to druby://localhost:42531"
  ].join("\n")

  opts.separator ""

  opts.on("-c", "--client-uri=uri",
    "Run the client on the specified uri.",
    "This can be used to specify the port",
    "that the client uses to allow for back",
    "connections from the server.",
    "Default: Find a good URI automatically.",
    "Example: -c druby://localhost:12345"
  ) { |options[:ClientURI]| }

  opts.on("-s", "--server-uri=uri",
    "Connect to the server specified at the",
    "specified uri.",
    "Default: druby://localhost:42531"
  ) { |options[:ServerURI]| }

  opts.on("-R", "--retry-delay=delay", Integer,
    "Automatically try to reconnect to the",
    "server after delay seconds when the",
    "connection failed or timed out.",
    "A value of 0 disables automatical",
    "reconnecting completely.",
    "Default: 10"
  ) { |options[:RetryDelay]| }

  opts.separator ""

  opts.on("-h", "--help",
    "Show this help message."
  ) { puts opts; exit }

  opts.parse!
end

options[:ServerURI] = ARGV[0] if ARGV[0]

DRb.start_service(options[:ClientURI])

begin
  service = DRbObject.new(nil, options[:ServerURI])

  begin
    service.register_eval_handler do |code|
      result = eval(code, TOPLEVEL_BINDING)
      result.extend(DRb::DRbUndumped) rescue nil
      result
    end

    service.register_collision_handler do
      msg = [
        "  *** Breakpoint service collision ***",
        "  Another Breakpoint service tried to use the",
        "  port already occupied by this one. It will",
        "  keep waiting until this Breakpoint service",
        "  is shut down.",
        "  ",
        "  If you are using the Breakpoint library for",
        "  debugging a Rails or other CGI application",
        "  this likely means that this Breakpoint",
        "  session belongs to an earlier, outdated",
        "  request and should be shut down via 'exit'."
      ].join("\n")

      if RUBY_PLATFORM["win"] then
        # This sucks. Sorry, I'm not doing this because
        # I like funky message boxes -- I need to do this
        # because on Windows I have no way of displaying
        # my notification via puts() when gets() is still
        # being performed on STDIN. I have not found a
        # better solution.
        begin
          require 'tk'
          root = TkRoot.new { withdraw }
          Tk.messageBox('message' => msg, 'type' => 'ok')
          root.destroy
        rescue Exception
          puts "", msg, ""
        end
      else
        puts "", msg, ""
      end
    end

    service.register_handler do |workspace, message|
      puts message
      IRB.start(nil, nil, workspace)
    end

    loop do
      begin
        service.ping
      rescue DRb::DRbConnError => error
        puts "Server exited. Exiting..."
        exit!
      end

      sleep(0.5)
    end
  ensure
    service.unregister_handler
  end
rescue Exception => error
  if options[:RetryDelay] > 0 then
    puts "No connection to breakpoint service at #{options[:ServerURI]}:",
         "  (#{error})",
         "  Reconnecting in #{options[:RetryDelay]} seconds..."
 
    sleep options[:RetryDelay]
    retry
  else
    raise
  end
end