#include <stdint.h>

#include "i2s.pio.h"
#include "nxs_audio.h"
#include "nxs_test.h"

int main(void) {
    const uint32_t words[] = {0x01234567, 0x89abcdef, 0x7fffff00, 0x80000000, 0, 0xffffffff, 0x55555555, 0xaaaaaaaa};
    uint32_t captured[sizeof(words) / sizeof(words[0])] = {0};
    size_t word_count = sizeof(words) / sizeof(words[0]);
    size_t program_counter = nxs_i2s_wrap_target, loaded_words = 0, captured_bits = 0;
    uint32_t counter = 0, shift_register = 0;
    unsigned int bits_remaining = 0, data_pin = 0;
    for (size_t cycle = 0; cycle <= word_count * NXS_I2S_BITS_PER_SLOT * 2u; ++cycle) {
        uint16_t instruction = nxs_i2s_program_instructions[program_counter];
        unsigned int side = (instruction >> 11) & 3u;
        CHECK((instruction & 0x0700u) == 0);
        CHECK((side & 1u) == ((cycle + 1u) & 1u));
        size_t next = program_counter == nxs_i2s_wrap ? nxs_i2s_wrap_target : program_counter + 1;
        switch (instruction & 0xe000u) {
        case 0xe000:
            CHECK(((instruction >> 5) & 7u) == 1);
            counter = instruction & 31u;
            break;
        case 0x6000:
            CHECK(((instruction >> 5) & 7u) == 0 && (instruction & 31u) == 1);
            if (bits_remaining == 0) {
                CHECK(loaded_words < word_count);
                shift_register = words[loaded_words++];
                bits_remaining = NXS_I2S_BITS_PER_SLOT;
            }
            data_pin = shift_register >> 31;
            shift_register <<= 1;
            --bits_remaining;
            break;
        case 0x0000:
            CHECK(((instruction >> 5) & 7u) == 2);
            if (counter-- != 0) {
                next = instruction & 31u;
            }
            break;
        default:
            CHECK(false);
        }
        if ((side & 1u) && cycle != 0) {
            size_t word = captured_bits / NXS_I2S_BITS_PER_SLOT;
            unsigned int bit = 31u - (unsigned int)(captured_bits % NXS_I2S_BITS_PER_SLOT);
            CHECK(word < word_count);
            CHECK((side >> 1) == ((word & 1u) ^ (bit == 0)));
            captured[word] = (captured[word] << 1) | data_pin;
            ++captured_bits;
        }
        program_counter = next;
    }
    CHECK(captured_bits == word_count * NXS_I2S_BITS_PER_SLOT);
    CHECK(NXS_I2S_CYCLES_PER_FRAME == NXS_AUDIO_CHANNELS * NXS_I2S_BITS_PER_SLOT * 2u);
    for (size_t word = 0; word < word_count; ++word) {
        CHECK(captured[word] == words[word]);
    }
    return nxs_test_finish("PIO waveform model");
}
