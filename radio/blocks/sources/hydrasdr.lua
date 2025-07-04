---
-- Source a complex-valued signal from an HydraSDR. This source requires the
-- libhydrasdr library. The HydraSDR RFOne is supported.
--
-- @category Sources
-- @block HydraSDRSource
-- @tparam number frequency Tuning frequency in Hz
-- @tparam number rate Sample rate in Hz (2.5 MHz, 5 MHz or 10 MHz for HydraSDR RFOne)
-- @tparam[opt={}] table options Additional options, specifying:
--      * `gain_mode` (string, default "linearity", choice of "custom", "linearity", "sensitivity")
--      * `lna_gain` (int, default 5 dB, for custom gain mode, range 0 to 15 dB)
--      * `mixer_gain` (int, default 1 dB, for custom gain mode, range 0 to 15 dB)
--      * `vga_gain` (int, default 5 dB, for custom gain mode, range 0 to 15 dB)
--      * `lna_agc` (bool, default false, for custom gain mode)
--      * `mixer_agc` (bool, default false, for custom gain mode)
--      * `linearity_gain` (int, default 10, for linearity gain mode, range 0 to 21)
--      * `sensitivity_gain` (int, default 9, for sensitivity gain mode, range 0 to 21 but max for better use is 9 maximum to avoid spurs)
--      * `biastee_enable` (bool, default false)
--
-- @signature > out:ComplexFloat32
--
-- @usage
-- -- Source samples from 135 MHz sampled at 6 MHz
-- local src = radio.HydraSDRSource(135e6, 6e6)
--
-- -- Source samples from 91.1 MHz sampled at 3 MHz, with custom gain settings
-- local src = radio.HydraSDRSource(91.1e6, 3e6, {gain_mode = "custom", lna_gain = 4,
--                                              mixer_gain = 1, vga_gain = 6})
--
-- -- Source samples from 91.1 MHz sampled at 2.5 MHz, with linearity gain mode
-- local src = radio.HydraSDRSource(91.1e6, 2.5e6, {gain_mode = "linearity", linearity_gain = 8})
--
-- -- Source samples from 91.1 MHz sampled at 2.5 MHz, with sensitivity gain mode
-- local src = radio.HydraSDRSource(91.1e6, 2.5e6, {gain_mode = "sensitivity", sensitivity_gain = 8})
--
-- -- Source samples from 144.390 MHz sampled at 2.5 MHz, with bias tee enabled
-- local src = radio.HydraSDRSource(144.390e6, 2.5e6, {biastee_enable = true})

local ffi = require('ffi')

local block = require('radio.core.block')
local platform = require('radio.core.platform')
local debug = require('radio.core.debug')
local types = require('radio.types')
local async = require('radio.core.async')
local pipe = require('radio.core.pipe')

local HydraSDRSource = block.factory("HydraSDRSource")

function HydraSDRSource:instantiate(frequency, rate, options)
    self.frequency = assert(frequency, "Missing argument #1 (frequency)")
    self.rate = assert(rate, "Missing argument #2 (rate)")

    self.options = options or {}
    self.gain_mode = self.options.gain_mode or "linearity"
    self.biastee_enable = self.options.biastee_enable or false

    if self.gain_mode == "custom" then
        self.lna_gain = self.options.lna_gain or 5
        self.mixer_gain = self.options.mixer_gain or 1
        self.vga_gain = self.options.vga_gain or 5
        self.lna_agc = self.options.lna_agc or false
        self.mixer_agc = self.options.mixer_agc or false
    elseif self.gain_mode == "linearity" then
        self.linearity_gain = self.options.linearity_gain or 10
    elseif self.gain_mode == "sensitivity" then
        self.sensitivity_gain = self.options.sensitivity_gain or 9
    else
        error(string.format("Unsupported gain mode \"%s\".", self.gain_mode))
    end

    self:add_type_signature({}, {block.Output("out", types.ComplexFloat32)})
end

function HydraSDRSource:get_rate()
    return self.rate
end

ffi.cdef[[
    enum hydrasdr_error { HYDRASDR_SUCCESS = 0, };
    enum hydrasdr_board_id { HYDRASDR_BOARD_ID_PROTO_HYDRASDR = 0, };
    enum hydrasdr_sample_type { HYDRASDR_SAMPLE_FLOAT32_IQ = 0, };

    struct hydrasdr_device;

    typedef struct {
        uint32_t major_version;
        uint32_t minor_version;
        uint32_t revision;
    } hydrasdr_lib_version_t;

    typedef struct {
        struct hydrasdr_device* device;
        void* ctx;
        void* samples;
        int sample_count;
        uint64_t dropped_samples;
        enum hydrasdr_sample_type sample_type;
    } hydrasdr_transfer_t, hydrasdr_transfer;

    typedef int (*hydrasdr_sample_block_cb_fn)(hydrasdr_transfer* transfer);

    const char* hydrasdr_error_name(enum hydrasdr_error errcode);

    int hydrasdr_open(struct hydrasdr_device** device);
    int hydrasdr_close(struct hydrasdr_device* device);

    void hydrasdr_lib_version(hydrasdr_lib_version_t* lib_version);
    int hydrasdr_board_id_read(struct hydrasdr_device* device, uint8_t* value);
    const char* hydrasdr_board_id_name(enum hydrasdr_board_id board_id);
    int hydrasdr_version_string_read(struct hydrasdr_device* device, char* version, uint8_t length);

    int hydrasdr_start_rx(struct hydrasdr_device* device, hydrasdr_sample_block_cb_fn callback, void* rx_ctx);
    int hydrasdr_stop_rx(struct hydrasdr_device* device);

    int hydrasdr_get_samplerates(struct hydrasdr_device* device, uint32_t* buffer, const uint32_t len);
    int hydrasdr_set_samplerate(struct hydrasdr_device* device, uint32_t samplerate);

    int hydrasdr_set_sample_type(struct hydrasdr_device* device, enum hydrasdr_sample_type sample_type);
    int hydrasdr_set_freq(struct hydrasdr_device* device, const uint32_t freq_hz);
    int hydrasdr_set_lna_gain(struct hydrasdr_device* device, uint8_t value);
    int hydrasdr_set_mixer_gain(struct hydrasdr_device* device, uint8_t value);
    int hydrasdr_set_vga_gain(struct hydrasdr_device* device, uint8_t value);
    int hydrasdr_set_lna_agc(struct hydrasdr_device* device, uint8_t value);
    int hydrasdr_set_mixer_agc(struct hydrasdr_device* device, uint8_t value);
    int hydrasdr_set_linearity_gain(struct hydrasdr_device* device, uint8_t value);
    int hydrasdr_set_sensitivity_gain(struct hydrasdr_device* device, uint8_t value);
    int hydrasdr_set_rf_bias(struct hydrasdr_device* device, uint8_t value);
    int hydrasdr_set_packing(struct hydrasdr_device* device, uint8_t value);
]]
local libhydrasdr_available, libhydrasdr = pcall(ffi.load, "hydrasdr")

function HydraSDRSource:initialize()
    -- Check library is available
    if not libhydrasdr_available then
        error("HydraSDRSource: libhydrasdr not found. Is libhydrasdr installed?")
    end
end

function HydraSDRSource:initialize_hydrasdr()
    self.dev = ffi.new("struct hydrasdr_device *[1]")

    local ret

    -- Open device
    ret = libhydrasdr.hydrasdr_open(self.dev)
    if ret ~= 0 then
        error("hydrasdr_open(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
    end

    -- Dump version info
    if debug.enabled then
        -- Look up library version
        local lib_version = ffi.new("hydrasdr_lib_version_t")
        libhydrasdr.hydrasdr_lib_version(lib_version)

        -- Look up firmware version
        local firmware_version = ffi.new("char[128]")
        ret = libhydrasdr.hydrasdr_version_string_read(self.dev[0], firmware_version, 128)
        if ret ~= 0 then
            error("hydrasdr_version_string_read(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
        end
        firmware_version = ffi.string(firmware_version)

        -- Look up board ID
        local board_id = ffi.new("uint8_t[1]")
        ret = libhydrasdr.hydrasdr_board_id_read(self.dev[0], board_id)
        if ret ~= 0 then
            error("hydrasdr_board_id_read(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
        end
        board_id = ffi.string(libhydrasdr.hydrasdr_board_id_name(board_id[0]))

        debug.printf("[HydraSDRSource] Library version:   %u.%u.%u\n", lib_version.major_version, lib_version.minor_version, lib_version.revision)
        debug.printf("[HydraSDRSource] Firmware version:  %s\n", firmware_version)
        debug.printf("[HydraSDRSource] Board ID:          %s\n", board_id)
    end

    -- Set sample type
    ret = libhydrasdr.hydrasdr_set_sample_type(self.dev[0], ffi.C.HYDRASDR_SAMPLE_FLOAT32_IQ)
    if ret ~= 0 then
        error("hydrasdr_set_sample_type(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
    end

    -- Set sample rate
    ret = libhydrasdr.hydrasdr_set_samplerate(self.dev[0], self.rate)
    if ret ~= 0 then
        local ret_save = ret

        io.stderr:write(string.format("[HydraSDRSource] Error setting sample rate %u S/s.\n", self.rate))

        local num_sample_rates, sample_rates

        -- Look up number of sample rates
        num_sample_rates = ffi.new("uint32_t[1]")
        ret = libhydrasdr.hydrasdr_get_samplerates(self.dev[0], num_sample_rates, 0)
        if ret ~= 0 then
            goto set_samplerate_error
        end

        -- Look up sample rates
        sample_rates = ffi.new("uint32_t[?]", num_sample_rates[0])
        ret = libhydrasdr.hydrasdr_get_samplerates(self.dev[0], sample_rates, num_sample_rates[0])
        if ret ~= 0 then
            goto set_samplerate_error
        end

        -- Print supported sample rates
        io.stderr:write("[HydraSDRSource] Supported sample rates:\n")
        for i=0, num_sample_rates[0]-1 do
            io.stderr:write(string.format("[HydraSDRSource]    %u\n", sample_rates[i]))
        end

        ::set_samplerate_error::
        error("hydrasdr_set_samplerate(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret_save)))
    end

    debug.printf("[HydraSDRSource] Frequency: %u Hz, Sample rate: %u Hz\n", self.frequency, self.rate)

    -- Disable packing
    ret = libhydrasdr.hydrasdr_set_packing(self.dev[0], 0)
    if ret ~= 0 then
        error("hydrasdr_set_packing(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
    end

    -- Set bias tee
    ret = libhydrasdr.hydrasdr_set_rf_bias(self.dev[0], self.biastee_enable)
    if ret ~= 0 then
        error("hydrasdr_set_rf_bias(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
    end

    if self.gain_mode == "custom" then
        -- LNA gain
        if not self.lna_agc then
            -- Disable LNA AGC
            ret = libhydrasdr.hydrasdr_set_lna_agc(self.dev[0], 0)
            if ret ~= 0 then
                error("hydrasdr_set_lna_agc(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
            end

            -- Set LNA gain
            ret = libhydrasdr.hydrasdr_set_lna_gain(self.dev[0], self.lna_gain)
            if ret ~= 0 then
                error("hydrasdr_set_lna_gain(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
            end
        else
            -- Enable LNA AGC
            ret = libhydrasdr.hydrasdr_set_lna_agc(self.dev[0], 1)
            if ret ~= 0 then
                error("hydrasdr_set_lna_agc(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
            end
        end

        -- Mixer gain
        if not self.mixer_agc then
            -- Disable mixer AGC
            ret = libhydrasdr.hydrasdr_set_mixer_agc(self.dev[0], 0)
            if ret ~= 0 then
                error("hydrasdr_set_mixer_agc(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
            end

            -- Set mixer gain
            ret = libhydrasdr.hydrasdr_set_mixer_gain(self.dev[0], self.mixer_gain)
            if ret ~= 0 then
                error("hydrasdr_set_mixer_gain(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
            end
        else
            -- Enable mixer AGC
            ret = libhydrasdr.hydrasdr_set_mixer_agc(self.dev[0], 1)
            if ret ~= 0 then
                error("hydrasdr_set_mixer_agc(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
            end
        end

        -- Set VGA gain
        ret = libhydrasdr.hydrasdr_set_vga_gain(self.dev[0], self.vga_gain)
        if ret ~= 0 then
            error("hydrasdr_set_vga_gain(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
        end
    elseif self.gain_mode == "linearity" then
        -- Set linearity gain
        ret = libhydrasdr.hydrasdr_set_linearity_gain(self.dev[0], self.linearity_gain)
        if ret ~= 0 then
            error("hydrasdr_set_linearity_gain(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
        end
    elseif self.gain_mode == "sensitivity" then
        -- Set sensitivity gain
        ret = libhydrasdr.hydrasdr_set_sensitivity_gain(self.dev[0], self.sensitivity_gain)
        if ret ~= 0 then
            error("hydrasdr_set_sensitivity_gain(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
        end
    end

    -- Set frequency
    ret = libhydrasdr.hydrasdr_set_freq(self.dev[0], self.frequency)
    if ret ~= 0 then
        error("hydrasdr_set_freq(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
    end
end

local function read_callback_factory(...)
    local ffi = require('ffi')

    local radio = require('radio')
    local pipe = require('radio.core.pipe')
    local vector = require('radio.core.vector')

    -- Convert fds on stack to Pipe objects
    local output_pipes = {}
    for i, fd in ipairs({...}) do
        output_pipes[i] = pipe.Pipe()
        output_pipes[i]:initialize(radio.types.ComplexFloat32, nil, fd)
    end

    -- Create pipe mux for write multiplexing
    local pipe_mux = pipe.PipeMux({}, {output_pipes})

    local function read_callback(transfer)
        -- Check for dropped samples
        if transfer.dropped_samples ~= 0 then
            io.stderr:write(string.format("[HydraSDRSource] Warning: %u samples dropped.\n", tonumber(transfer.dropped_samples)))
        end

        -- Calculate size of samples in bytes
        local size = transfer.sample_count*ffi.sizeof("float")*2

        -- Write to output pipes
        local eof, eof_pipe, shutdown = pipe_mux:write({vector.Vector.cast(radio.types.ComplexFloat32, transfer.samples, size)})
        if not shutdown and eof then
            io.stderr:write("[HydraSDRSource] Downstream block terminated unexpectedly.\n")
        end

        return 0
    end

    return ffi.cast('int (*)(hydrasdr_transfer *)', read_callback)
end

function HydraSDRSource:run()
    -- Initialize the hydrasdr in our own running process
    self:initialize_hydrasdr()

    -- Create pipe mux for control socket
    local pipe_mux = pipe.PipeMux({}, {}, self.control_socket)

    -- Start receiving
    local read_callback, read_callback_state = async.callback(read_callback_factory, unpack(self.outputs[1]:filenos()))
    local ret = libhydrasdr.hydrasdr_start_rx(self.dev[0], read_callback, nil)
    if ret ~= 0 then
        error("hydrasdr_start_rx(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
    end

    -- Wait for shutdown from control socket
    while true do
        -- Read control socket
        local _, _, shutdown = pipe_mux:read()
        if shutdown then
            break
        end
    end

    -- Stop receiving
    ret = libhydrasdr.hydrasdr_stop_rx(self.dev[0])
    if ret ~= 0 then
        error("hydrasdr_stop_rx(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
    end

    -- Close hydrasdr
    ret = libhydrasdr.hydrasdr_close(self.dev[0])
    if ret ~= 0 then
        error("hydrasdr_close(): " .. ffi.string(libhydrasdr.hydrasdr_error_name(ret)))
    end
end

return HydraSDRSource
