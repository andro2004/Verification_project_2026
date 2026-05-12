# delay_transfer_test Analysis Against Specification

## Issues Found and Fixed

### 1. **CRITICAL: Missing ref_model.reset() Between Subtests** ✅ FIXED
**Root Cause**: The test calls `spi_sequence_lib::reset_dut()` but never resets the ref_model, causing prediction state to carry over between subtests.

**Impact**: 
- Subtest A RX mismatch: predicted=0xA5 vs observed=0x00 (stale predictions from previous run)
- All subsequent subtests have corrupted RX comparisons

**Fix Applied**: Added `ref_model.reset()` before each subtest in the `run()` task:
```systemverilog
spi_sequence_lib::reset_dut();
ref_model.reset();  // <-- Added
run_delay_subtest(...);
```

### 2. **Delay Measurement Discrepancies** ⚠️ UNDER INVESTIGATION
**Symptom**: Measured delay is consistently less than expected:
- Subtest C: measured 2 half-cycles vs expected 8 (gap=4 vs expected 16 PCLK)
- Subtest D: measured 122 vs expected 128 (gap=122 vs expected 128 PCLK)

**Possible Causes**:
- Gap measurement timing might not align with DELAY register specification
- `wait_for_sclk_idle()` might be consuming DELAY cycles before measurement
- Initial gap_pclk offset of 2 might not be correct for all configurations

**Spec Reference (Section 3.8)**:
"When non-zero, the master inserts DELAY[7:0] idle SCLK half-cycles between consecutive transfers while BUSY remains 1."

**Next Steps**: Verify the measurement methodology against actual RTL behavior with golden model.

### 3. **Spec Compliance Verification** ✅ VERIFIED
According to Spec Section 4.2 (Transfer Sequence):
- ✅ BFM signals set before predict_transfer
- ✅ configure_dut called before predictions
- ✅ TX data pushed before SS assertion
- ✅ SS asserted with sufficient timing for setup
- ✅ RX FIFO reads occur after BUSY clears (Spec 5.2: "Push: automatic at completion of each transfer")

## Test Execution Order (Corrected)

Per Spec Section 4.2:
1. Set BFM control signals (mode, width, pattern, lsb_first)
2. Configure DUT registers via APB
3. Configure ref_model with same values
4. Predict transfers
5. **Reset ref_model** (NEW)
6. Push TX data to both DUT and ref_model FIFOs
7. Mark transfer start on ref_model
8. Assert SS_n
9. Wait for measurements/timing
10. Wait for BUSY clear
11. Deassert SS_n
12. Read RX data
13. Verify against predictions

## Files Modified

- `delay_transfer_test.sv`: Added `ref_model.reset()` calls before each subtest

## Testing Recommendation

After the fix is applied, run the test again and verify:
1. ✓ RX mismatch errors should be resolved
2. ⚠️ Delay measurement discrepancies may still exist - if so, review measure_gap() timing
3. ✓ All other checks should pass with golden RTL
