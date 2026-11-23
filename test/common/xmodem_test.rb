# frozen_string_literal: true

require 'test_helper'

class XmodemTest < Minitest::Test
  X = Rubbs::Common::Files::Xmodem

  # One end of a plain byte pipe between a sender and a receiver.
  class PipeEnd
    attr_reader :written

    def initialize(input, output)
      @input   = input
      @output  = output
      @written = +''.b
    end

    def self.pair
      a_in, b_out = IO.pipe
      b_in, a_out = IO.pipe
      [new(a_in, a_out), new(b_in, b_out)]
    end

    def read_raw_byte(timeout)
      return :timeout unless @input.wait_readable(timeout)

      @input.read(1)&.ord
    end

    def write_raw(bytes)
      @written << bytes.b
      @output.write(bytes)
    rescue IOError, SystemCallError
      nil
    end

    def close = [@input, @output].each { |io| io.close unless io.closed? }
  end

  def setup
    @board, @terminal = PipeEnd.pair
  end

  def teardown
    [@board, @terminal].each(&:close)
  end

  def data(size) = Random.new(size).bytes(size).b.tap { |d| d[5, 4] = "\x18\x18\xFF\x1A".b if size > 9 }

  def receive(**) = X.receive_file(@board, telnet: false, **)

  def send_in_background(bytes, one_k: false)
    Thread.new { X.send_file(@terminal, bytes, telnet: false, one_k: one_k) }
  end

  def test_a_crc_upload_comes_in_padded_to_its_block
    sent = data(300)
    sender = send_in_background(sent)
    got = receive
    assert_equal :ok, sender.value
    assert_equal 384, got.bytesize
    assert_equal sent, got[0, 300]
    assert_equal "\x1A".b * 84, got[300..]
    assert_equal 'C', @board.written[0]
  end

  def test_1k_blocks_are_taken
    sent = data(2000)
    sender = send_in_background(sent, one_k: true)
    got = receive
    assert_equal :ok, sender.value
    assert_equal 2048, got.bytesize
    assert_equal sent, got[0, 2000]
  end

  # A sender of the checksum kind, whatever the receiver asked for.
  def script(frames)
    Thread.new do
      @terminal.read_raw_byte(5)
      frames.each do |frame|
        @terminal.write_raw(frame)
        @terminal.read_raw_byte(10)
      end
    end
  end

  def test_a_checksum_sender_is_read_after_a_crc_start
    chunk = data(128)
    script([X.frame(1, chunk, crc: false), X::EOT.chr])
    assert_equal chunk, receive
  end

  def test_a_broken_block_is_asked_for_again
    chunk  = data(128)
    broken = X.frame(1, chunk, crc: true).dup
    broken[10] = (broken[10].ord ^ 1).chr
    script([broken, X.frame(1, chunk, crc: true), X::EOT.chr])
    assert_equal chunk, receive
    assert_includes @board.written, X::NAK.chr
  end

  def test_a_block_sent_twice_is_kept_once
    chunk = data(128)
    frame = X.frame(1, chunk, crc: true)
    script([frame, frame, X.frame(2, chunk, crc: true), X::EOT.chr])
    assert_equal chunk * 2, receive
  end

  def test_a_block_out_of_order_fails
    script([X.frame(3, data(128), crc: true)])
    assert_equal :failed, receive
    assert_includes @board.written, X::ABORT
  end

  def test_a_file_past_max_bytes_is_cancelled
    sender = send_in_background(data(1000))
    assert_equal :too_large, receive(max_bytes: 256)
    assert_includes @board.written, X::ABORT
    assert_includes %i[cancelled timeout], sender.value
  end

  def test_the_caller_gives_up_with_escape
    @terminal.write_raw("\e")
    assert_equal :cancelled, receive
  end

  def test_two_cans_cancel
    @terminal.write_raw("\x18\x18")
    assert_equal :cancelled, receive
  end

  def test_no_sender_is_a_timeout
    assert_equal :timeout, receive(wait: 0.2)
  end

  def test_a_hangup_is_reported
    @terminal.close
    assert_equal :hangup, receive
  end

  def test_iac_comes_through_a_telnet_line
    line  = FakeLine.new
    board = FakeSession.new(line)
    terminal = Rubbs::Common::Line::Session.new(line.caller)
    sent = data(200)
    sender = Thread.new { X.send_file(terminal, sent, telnet: true) }
    got = X.receive_file(board, telnet: true)
    assert_equal :ok, sender.value
    assert_equal sent, got[0, 200]
  ensure
    line&.close
  end

  def test_transfer_receive_raises_on_hangup_and_words_the_results
    Rubbs::Common::Files::Xmodem.stub(:receive_file, :hangup) do
      assert_raises(Rubbs::Common::Line::Hangup) { Rubbs::Common::Files::Transfer.receive(@board, max_bytes: 10) }
    end
    assert_nil Rubbs::Common::Files::Transfer.upload_result('bytes')
    assert_match(/too large/, Rubbs::Common::Files::Transfer.upload_result(:too_large))
    assert_match(/XMODEM upload of your picture/, Rubbs::Common::Files::Transfer.upload_start('your picture'))
  end
end
