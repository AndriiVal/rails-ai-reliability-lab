class ReliabilityTestTime
  attr_reader :sleeps

  def initialize
    @now = 0.0
    @sleeps = []
  end

  def call
    @now
  end

  def wall_time
    Time.utc(2026, 1, 1) + @now
  end

  def advance(seconds)
    @now += seconds
  end

  def sleep(seconds)
    @sleeps << seconds
    advance(seconds)
  end
end
