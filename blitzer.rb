#!/usr/bin/env ruby

# http://blitz.io
# http://www.mudynamics.com
# http://altiora.es
# Making load and performance testing a fun sport!

begin
  require 'rubygems'
  require 'blitz'
  require 'heroku-api'
rescue Exception
  puts 'Blitzer requires the following gems to be installed:'
  puts 'blitz'
  puts 'heroku-api'
  exit
end

class Blitzer
    ERROR_TOLERANCE = 2 # percentage of errors

    attr_reader :heroku
    attr_reader :app
    attr_reader :target

    def initialize opts
        @heroku = Heroku::API.new(:api_key => opts[:api_key])
        @app    = opts[:app]
        @target = opts[:target]
    end

    # Kick off the number of dynos and wait until all those are up. We do
    # this by checking the state of each dyno until it's up.
    def set_dynos qty
        progress "starting #{qty} dyno(s) "

        heroku.post_ps_scale(app, :web, qty)
        while true
            progress "."
            sleep 1.0
            dynos = heroku.get_ps(app).body
            break if dynos.size == qty and dynos.all? { |d| d['state'] == 'up' }
        end

        progress "done\n"
    end

    def run
        [ 1, 2, 4, 8, 16, 32 ].each do |dyno|
            set_dynos dyno

            # The :status => 200 makes http://blitz.io generate an error when
            # we receive something other than 200 Okay during the load test.
            # And Heroku generates a 500 error when this happens so it allows
            # us to detect that the app crashed.
            opts = "--region virginia " +
                   "--pattern 1-#{target}:30 " +
                   "--status 200 " +
                   "http://#{app}.herokuapp.com"

            puts opts

            progress "  rushing "
            status = Blitz::Curl.parse(opts).execute() do |s|
                progress "."
                last = s.timeline[-1]

                # Abort the rush, if the error rate is higher than 1%
                percent_errors = 100 - (last.hits * 100 / last.total)
                if percent_errors >= ERROR_TOLERANCE
                    ary = []
                    ary << "#{last.hits} hits"
                    ary << "#{last.errors} errors" if last.errors
                    ary << "#{last.timeouts} timeouts" if last.timeouts
                    progress "#{ary.join(' | ')} @ #{last.volume} users\n"
                end

                percent_errors < ERROR_TOLERANCE
            end

            # When there are no more errors, we've reached the
            # optimimum number of dynos for the target concurrency.
            last = status.timeline[-1]
            percent_errors = 100 - (last.hits * 100 / last.total)
            if percent_errors < ERROR_TOLERANCE
                progress "done\n\n"
                progress ">> You need #{dyno} dyno(s) to handle #{target} concurrent users!\n\n"
                break
            end
        end

        # Reset the dynos back to 1
        heroku.post_ps_scale(app, 'web', 1)
    end

    def progress text
        $stdout.print text
        $stdout.flush
    end
end

if ARGV.size < 2
    puts "Usage: blitzer api_key heroku_app [target]"
    puts "api_key - Heroku API key (from the accounts page)"
    puts "app     - The name of your heroku app"
    puts "target  - How many users do you want to get to? default = 1000"
    exit 1
end

opts = Hash.new
opts[:api_key]   = ARGV.shift
opts[:app]    = ARGV.shift
opts[:target] = (ARGV.shift || 250).to_i

puts "Blitzing http://#{opts[:app]}.herokuapp.com with a target of #{opts[:target]} users"
puts
blitzer = Blitzer.new opts
blitzer.run
