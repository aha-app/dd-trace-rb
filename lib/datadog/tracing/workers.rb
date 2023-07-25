require_relative 'buffer'
require_relative 'pipeline'
# require 'cli/ui'

module Datadog
  module Tracing
    module Workers
      # Asynchronous worker that executes a +Send()+ operation after given
      # seconds. Under the hood, it uses +Concurrent::TimerTask+ so that the thread
      # will perform a task at regular intervals. The thread can be stopped
      # with the +stop()+ method and can start with the +start()+ method.
      class AsyncTransport
        DEFAULT_BUFFER_MAX_SIZE = 1000
        DEFAULT_FLUSH_INTERVAL = 1
        DEFAULT_TIMEOUT = 5
        BACK_OFF_RATIO = 1.2
        BACK_OFF_MAX = 5
        SHUTDOWN_TIMEOUT = 1

        attr_reader \
          :trace_buffer

        def initialize(options = {})
          @transport = options[:transport]

          # Callbacks
          @trace_task = options[:on_trace]

          # Intervals
          interval = options.fetch(:interval, DEFAULT_FLUSH_INTERVAL)
          @flush_interval = interval
          @back_off = interval

          # Buffers
          buffer_size = options.fetch(:buffer_size, DEFAULT_BUFFER_MAX_SIZE)
          @trace_buffer = TraceBuffer.new(buffer_size)

          # Threading
          @shutdown = ConditionVariable.new
          @mutex = Mutex.new
          @worker = nil
          @run = false
        end

        # Callback function that process traces and executes the +send_traces()+ method.
        def callback_traces
          File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Flushing traces\n") }
          return true if @trace_buffer.empty?

          begin
            traces = @trace_buffer.pop
            traces = Pipeline.process!(traces)
            @trace_task.call(traces, @transport) unless @trace_task.nil? || traces.empty?
          rescue StandardError => e
            # ensures that the thread will not die because of an exception.
            # TODO[manu]: findout the reason and reschedule the send if it's not
            # a fatal exception
            Datadog.logger.error(
              "Error during traces flush: dropped #{traces.length} items. Cause: #{e} Location: #{Array(e.backtrace).first}"
            )
          end
        end

        # Start the timer execution.
        def start
          @mutex.synchronize do
            return if @run

            @run = true
            Datadog.logger.debug { "Starting thread for: #{self}" }
            @worker = Thread.new { perform }
            @worker.name = self.class.name unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3')

            nil
          end
        end

        # Closes all available queues and waits for the trace buffer to flush
        def stop
          File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb STOP waiting for mutex\n") }
          @mutex.synchronize do
            File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb STOP got mutex\n") }
            return unless @run

            @trace_buffer.close
            @run = false

            File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Sending shutdown signal\n") }
            # byebug
            @shutdown.signal
            File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Shutdown signal sent\n") }
          end

          join
          true
        end

        # Block until executor shutdown is complete or until timeout seconds have passed.
        def join
          File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Waiting for thread to join\n") }
          @worker.join(SHUTDOWN_TIMEOUT)
          File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Thread joined\n") }
        end

        # Enqueue an item in the trace internal buffer. This operation is thread-safe
        # because uses the +TraceBuffer+ data structure.
        def enqueue_trace(trace)
          return unless trace && !trace.empty?

          File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Enqueuing trace\n") }
          @trace_buffer.push(trace)
        end

        private

        alias flush_data callback_traces

        def perform
          File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Worker thread started\n") }

          loop do
            File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Worker thread flushing data\n") }
            @back_off = flush_data ? @flush_interval : [@back_off * BACK_OFF_RATIO, BACK_OFF_MAX].min
            File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Worker thread flushed data\n") }

            File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Worker thread waiting for mutex\n") }
            @mutex.synchronize do
              # sleep 11111

              if !@run && @trace_buffer.empty?
                File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Worker thread returning\n") }
                return
              end

              File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Worker thread continuing (#{@run}, #{@trace_buffer.empty?})\n") }

              if @run # do not wait when shutting down
                File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Worker thread releasing mutex (#{@back_off})\n") }
                # sleep 11111
                @shutdown.wait(@mutex, @back_off)
              end
            end
          end

          File.open('/tmp/ddtrace.txt', 'a') { |file| file.write("[#{Time.now}][#{Process.pid}][#{Thread.current.object_id}] workers.rb Worker thread outside loop(?)\n") }
        end
      end
    end
  end
end
