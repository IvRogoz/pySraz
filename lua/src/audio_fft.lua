-- src/audio_fft.lua
local U = require("src.util")

local AudioFFT = {}
AudioFFT.__index = AudioFFT

function AudioFFT:setVolume(v)
  v = math.max(0, math.min(1, v or 0))
  self.volume = v
  if self.source then
    self.source:setVolume(v)
  end
end

function AudioFFT.new(filename)
  local self = setmetatable({}, AudioFFT)

  self.filename = filename

  self.source = love.audio.newSource(filename, "stream")
  self.source:setLooping(true)
  self.source:play()

  self.volume = 0.5
  self.source:setVolume(self.volume)

  self.soundData = love.sound.newSoundData(filename)
  self.sampleRate = self.soundData:getSampleRate()
  self.channels = self.soundData:getChannels()
  self.sampleCount = self.soundData:getSampleCount()

  self.frameCount = math.floor(self.sampleCount / self.channels)

  self.FFT_TEX_W = 512
  self.FFT_TEX_H = 2
  self.FFT_WINDOW = 4096
  self.SMOOTH = 0.25

  self.prev = {}
  self.now = {}
  for i = 1, self.FFT_TEX_W do
    self.prev[i] = 0.0
    self.now[i] = 0.0
  end

  self.fftHz = 30
  self.fftAccum = 0

  self.hann = {}
  local N = self.FFT_WINDOW
  for n = 0, N - 1 do
    self.hann[n + 1] = 0.5 * (1.0 - math.cos((2.0 * math.pi * n) / (N - 1)))
  end

  self.re = {}
  self.im = {}
  for i = 1, N do
    self.re[i] = 0.0
    self.im[i] = 0.0
  end

  self.bitrev = {}
  do
    local bits = math.floor(math.log(N) / math.log(2) + 0.5)
    for i = 0, N - 1 do
      local x = i
      local y = 0
      for _ = 1, bits do
        y = y * 2 + (x % 2)
        x = math.floor(x / 2)
      end
      self.bitrev[i + 1] = y + 1
    end
  end

  self.twiddle = {}
  do
    local m = 2
    while m <= N do
      local half = m / 2
      local step = (2 * math.pi) / m
      local cosT = {}
      local sinT = {}
      for k = 0, half - 1 do
        cosT[k + 1] = math.cos(step * k)
        sinT[k + 1] = -math.sin(step * k)
      end
      self.twiddle[m] = {cos = cosT, sin = sinT}
      m = m * 2
    end
  end

  self.pixelFormat = U.isPixelFormatSupported("r8") and "r8" or "rgba8"
  self.imageData = love.image.newImageData(self.FFT_TEX_W, self.FFT_TEX_H, self.pixelFormat)
  self.image = love.graphics.newImage(self.imageData)
  self.image:setFilter("linear", "linear")
  self.image:setWrap("clamp", "clamp")

  return self
end

function AudioFFT:getTimeSeconds()
  local ok, pos = pcall(function() return self.source:tell("seconds") end)
  if ok and pos then return pos end
  return 0
end

function AudioFFT:getMonoSample(frameIndex)
  if self.channels == 1 then
    return self.soundData:getSample(frameIndex)
  else
    local base = frameIndex * self.channels
    local l = self.soundData:getSample(base)
    local r = self.soundData:getSample(base + 1)
    return 0.5 * (l + r)
  end
end

function AudioFFT:fftInPlace()
  local N = self.FFT_WINDOW
  local re, im = self.re, self.im

  local m = 2
  while m <= N do
    local half = m / 2
    local tw = self.twiddle[m]
    local cosT, sinT = tw.cos, tw.sin

    for start = 1, N, m do
      for k = 0, half - 1 do
        local i1 = start + k
        local i2 = i1 + half

        local wr = cosT[k + 1]
        local wi = sinT[k + 1]

        local tr = wr * re[i2] - wi * im[i2]
        local ti = wr * im[i2] + wi * re[i2]

        local ur = re[i1]
        local ui = im[i1]

        re[i1] = ur + tr
        im[i1] = ui + ti
        re[i2] = ur - tr
        im[i2] = ui - ti
      end
    end

    m = m * 2
  end
end

function AudioFFT:update(dt)
  self.fftAccum = self.fftAccum + dt
  local period = 1 / self.fftHz
  if self.fftAccum < period then
    return
  end
  self.fftAccum = self.fftAccum - period

  local t = self:getTimeSeconds()
  local centerFrame = math.floor((t * self.sampleRate)) % self.frameCount
  local half = math.floor(self.FFT_WINDOW / 2)
  local startFrame = centerFrame - half

  local N = self.FFT_WINDOW
  for i = 0, N - 1 do
    local f = startFrame + i
    f = f % self.frameCount
    if f < 0 then f = f + self.frameCount end

    local s = self:getMonoSample(f)
    s = s * self.hann[i + 1]

    local j = self.bitrev[i + 1]
    self.re[j] = s
    self.im[j] = 0.0
  end

  self:fftInPlace()

  local bins = (N / 2) + 1
  local mag = {}
  local maxv = 1e-9
  for k = 1, bins do
    local rr = self.re[k]
    local ii = self.im[k]
    local m = math.sqrt(rr * rr + ii * ii)
    m = math.log(1.0 + m)
    mag[k] = m
    if m > maxv then maxv = m end
  end
  for k = 1, bins do
    mag[k] = mag[k] / maxv
  end

  local take = math.max(32, math.floor(bins * 0.35))
  local W = self.FFT_TEX_W

  for x = 0, W - 1 do
    local pos = (x * (take - 1)) / (W - 1)
    local i0 = math.floor(pos)
    local frac = pos - i0
    local a = mag[i0 + 1] or 0
    local b = mag[i0 + 2] or a
    local v = a * (1 - frac) + b * frac

    v = U.clamp(v * 1.25, 0, 1)
    v = math.sqrt(v)
    self.now[x + 1] = v
  end

  for i = 1, W do
    self.prev[i] = (1 - self.SMOOTH) * self.prev[i] + self.SMOOTH * self.now[i]
  end

  if self.pixelFormat == "r8" then
    for x = 0, W - 1 do
      local v = self.prev[x + 1]
      self.imageData:setPixel(x, 0, v, 0, 0, 1)
      self.imageData:setPixel(x, 1, v, 0, 0, 1)
    end
  else
    for x = 0, W - 1 do
      local v = self.prev[x + 1]
      self.imageData:setPixel(x, 0, v, v, v, 1)
      self.imageData:setPixel(x, 1, v, v, v, 1)
    end
  end

  self.image:replacePixels(self.imageData)
end

return AudioFFT
