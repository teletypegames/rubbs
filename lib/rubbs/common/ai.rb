# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'yaml'

module Rubbs
  module Common
    # A conversational character for a BBS: a persona read from a YAML file, a
    # small model behind any OpenAI-compatible chat endpoint (llama.cpp's
    # llama-server, Ollama, vLLM, a hosted API, …), a short per-caller memory,
    # and canned replies for when the model is missing or fails.
    #
    #   PERSONA = Rubbs::Common::AI::Persona.load('lib/oracle.yml')
    #   ORACLE  = Rubbs::Common::AI::Chat.new(
    #     persona: PERSONA,
    #     client:  Rubbs::Common::AI::Client.new(url: ENV.fetch('ORACLE_LLM_URL', ''))
    #   )
    #
    #   on_unknown do |input, io|
    #     out = Rubbs::Common::AI::Typewriter.new(io, prefix: 'ORACLE: ', style: :dim)
    #     ORACLE.reply(input, io.ctx) { |piece| out.write(piece) }
    #     out.finish
    #   end
    #
    # With an empty URL the chat never calls a model and answers from the
    # persona's canned replies only, so a BBS can ship the character before it
    # has a model to run.
    module AI
      # Raised by Client when a request cannot be made or goes wrong in a way
      # of its own (the network and HTTP errors come as they are).
      class Error < StandardError; end

      # Raised by Client#stream when <tt>Rubbs.config.ai_concurrency</tt>
      # requests are running and none ended within Client::QUEUE_WAIT
      # seconds. Its message can be shown to the caller.
      class Busy < Error; end

      # Returns the seconds of the monotonic clock.
      def self.monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

require_relative 'ai/persona'
require_relative 'ai/semaphore'
require_relative 'ai/client'
require_relative 'ai/chat'
require_relative 'ai/typewriter'
