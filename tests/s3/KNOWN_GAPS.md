# s3 known gaps: unsound accepts

Every program below is rejected by s2c and accepted by s3c today: s3c emits C for it (exit 0). Each row is one gap: the repro is the file in tests/s2/neg, the Diag is what s2c prints. Delete the row in the commit that fixes it. Never special-case a test. Source: the neg run of 2026-11-14 (~/.cache/srs3/i50/neg.tsv, class EMIT, 129 rows).

| repro | expected Diag |
|---|---|
| tests/s2/neg/ambient_clock.srs | error[ambient-world] |
| tests/s2/neg/ambient_env.srs | error[ambient-world] |
| tests/s2/neg/ambient_files.srs | error[ambient-world] |
| tests/s2/neg/ambient_net.srs | error[ambient-world] |
| tests/s2/neg/ambient_pages.srs | error[ambient-world] |
| tests/s2/neg/array_assign.srs | error[assign-val] |
| tests/s2/neg/array_blit_partial.srs | error[index-unproved] |
| tests/s2/neg/array_blit_unproved.srs | error[index-unproved] |
| tests/s2/neg/array_escape.srs | error[region-escape] |
| tests/s2/neg/array_field.srs | error[mismatch] |
| tests/s2/neg/array_grow_copy_unproved.srs | error[index-unproved] |
| tests/s2/neg/array_grow_stale.srs | error[mismatch] |
| tests/s2/neg/array_loop.srs | error[length-unnamed] |
| tests/s2/neg/array_put_data_call.srs | error[put-data] |
| tests/s2/neg/array_put_data.srs | error[put-data] |
| tests/s2/neg/array_put_data_var.srs | error[put-data] |
| tests/s2/neg/array_put_nomut.srs | error[unhandled-effect] |
| tests/s2/neg/array_put_param_caller.srs | error[capability-bound] |
| tests/s2/neg/array_put_param_other.srs | error[capability-bound] |
| tests/s2/neg/array_put_param_unbound.srs | error[put-data] |
| tests/s2/neg/array_put_str_escape.srs | error[region-escape] |
| tests/s2/neg/array_put_unproved.srs | error[index-unproved] |
| tests/s2/neg/array_shadow.srs | error[index-unproved] |
| tests/s2/neg/array_slice.srs | error[slice-unproved] |
| tests/s2/neg/array_unproved.srs | error[index-unproved] |
| tests/s2/neg/array_var.srs | error[index-unproved] |
| tests/s2/neg/atom_list.srs | error[mismatch] |
| tests/s2/neg/atom_nocap.srs | error[no-capability] |
| tests/s2/neg/atom_noeffect.srs | error[unhandled-effect] |
| tests/s2/neg/atom_slot_range.srs | error[index-unproved] |
| tests/s2/neg/bytes_escape.srs | error[region-escape] |
| tests/s2/neg/bytes_len.srs | error[mismatch] |
| tests/s2/neg/call_targs.srs | error[arity] |
| tests/s2/neg/cap_ambig.srs | error[no-capability] |
| tests/s2/neg/cap_none.srs | error[no-capability] |
| tests/s2/neg/cap_norel.srs | error[parse] |
| tests/s2/neg/cap_order.srs | error[capability-not-ended] |
| tests/s2/neg/cap_param.srs | error[capability-param] |
| tests/s2/neg/cap_seq_many.srs | error[op-not-allowed] |
| tests/s2/neg/cap_seq_none.srs | error[op-not-allowed] |
| tests/s2/neg/cap_seq_open.srs | error[capability-not-ended] |
| tests/s2/neg/cap_value.srs | error[capability-value] |
| tests/s2/neg/caret_str_escape.srs | error[region-escape] |
| tests/s2/neg/caret_val.srs | error[use-after-free] |
| tests/s2/neg/cell_nomut.srs | error[unhandled-effect] |
| tests/s2/neg/cell_seal_block.srs | error[cell-seal] |
| tests/s2/neg/cell_seal_call.srs | error[cell-seal] |
| tests/s2/neg/chosen_count.srs | error[chosen-count] |
| tests/s2/neg/chosen_ev.srs | error[chosen-evidence] |
| tests/s2/neg/chosen_notcap.srs | error[chosen-not-capability] |
| tests/s2/neg/cstr_hides.srs | error[binder-hides-type] |
| tests/s2/neg/cstruct_name.srs | no '.' in its name |
| tests/s2/neg/cstruct_noabi.srs | error[parse] |
| tests/s2/neg/cstruct_type.srs | a libc struct field of type I32, I64, U32 or U64 |
| tests/s2/neg/double_free.srs | error[op-not-allowed] |
| tests/s2/neg/dup_case.srs | error[duplicate] |
| tests/s2/neg/dup_def.srs | error[duplicate] |
| tests/s2/neg/dup_lib.srs | error[duplicate] |
| tests/s2/neg/dup_type.srs | error[duplicate] |
| tests/s2/neg/eff_flow.srs | error[op-not-allowed] |
| tests/s2/neg/eff_handler_row.srs | error[unhandled-effect] |
| tests/s2/neg/eff_rt.srs | error[rt-outside-srs] |
| tests/s2/neg/eff_unhandled.srs | error[unhandled-effect] |
| tests/s2/neg/end_gone.srs | error[parse] |
| tests/s2/neg/erased_arg.srs | error[capability-erased] |
| tests/s2/neg/erased_extern.srs | error[capability-erased] |
| tests/s2/neg/erased_field.srs | error[capability-erased] |
| tests/s2/neg/erased_result.srs | error[capability-erased] |
| tests/s2/neg/ev_ambig_local.srs | error[ambiguous-evidence] |
| tests/s2/neg/ev_value.srs | error[evidence-value] |
| tests/s2/neg/extern_abi.srs | an extern ABI |
| tests/s2/neg/generic_hide.srs | error[binder-hides-type] |
| tests/s2/neg/group_facts.srs | error[fact-not-capability] |
| tests/s2/neg/group_out.srs | error[unknown-relation] |
| tests/s2/neg/handle_row_end.srs | error[region-ended-under-handle] |
| tests/s2/neg/handle_row_end_state.srs | error[region-ended-under-handle] |
| tests/s2/neg/handler_ptr_arg.srs | error[use-after-free] |
| tests/s2/neg/handler_ptr_binder.srs | error[capability-bound] |
| tests/s2/neg/handler_ptr_local.srs | error[capability-bound] |
| tests/s2/neg/handler_ptr_region.srs | error[capability-bound] |
| tests/s2/neg/handler_result_type.srs | error[mismatch] |
| tests/s2/neg/handler_trait.srs | error[not-a-capability] |
| tests/s2/neg/hstate_escape.srs | error[region-escape] |
| tests/s2/neg/hstate_init_region.srs | error[region-escape] |
| tests/s2/neg/hstate_mixed.srs | error[handler-state-type] |
| tests/s2/neg/hstate_shape.srs | error[handler-state-shape] |
| tests/s2/neg/libc_dotted.srs | no '.' in its name |
| tests/s2/neg/libc_outside.srs | error[libc-outside-handler] |
| tests/s2/neg/libc_val_dotted.srs | no '.' in its name |
| tests/s2/neg/libc_val_noabi.srs | error[parse] |
| tests/s2/neg/libc_val_type.srs | a libc val of type I32, I64 or U64 |
| tests/s2/neg/libc_variadic_i64.srs | error[mismatch] |
| tests/s2/neg/mod_dup.srs | error[duplicate] |
| tests/s2/neg/ms_answer.srs | error[answer-type] |
| tests/s2/neg/ms_resume_arg.srs | error[mismatch] |
| tests/s2/neg/ms_resume_not_k.srs | error[resume-not-k] |
| tests/s2/neg/net_after_close.srs | error[op-not-allowed] |
| tests/s2/neg/net_before_connect.srs | error[op-not-allowed] |
| tests/s2/neg/net_no_close.srs | error[capability-not-ended] |
| tests/s2/neg/op_binder_type.srs | error[op-binder] |
| tests/s2/neg/op_data_escape.srs | error[region-escape] |
| tests/s2/neg/op_param_arity.srs | error[handler-arity] |
| tests/s2/neg/op_param_type.srs | error[mismatch] |
| tests/s2/neg/op_ptr_binder.srs | error[use-after-free] |
| tests/s2/neg/op_ptr_escape.srs | error[region-escape] |
| tests/s2/neg/op_ptr_request.srs | error[use-after-free] |
| tests/s2/neg/op_ptr.srs | error[use-after-free] |
| tests/s2/neg/op_region_escape.srs | error[region-escape] |
| tests/s2/neg/op_region_noregion.srs | error[no-capability] |
| tests/s2/neg/op_region_row_noregion.srs | error[unhandled-effect] |
| tests/s2/neg/op_region_sig.srs | error[op-signature] |
| tests/s2/neg/op_result_cap.srs | error[op-result-capability] |
| tests/s2/neg/op_result_escape_nested.srs | error[region-escape] |
| tests/s2/neg/op_result_escape.srs | error[region-escape] |
| tests/s2/neg/op_str_escape.srs | error[region-escape] |
| tests/s2/neg/os_rt_outside.srs | error[rt-outside-srs] |
| tests/s2/neg/os_unhandled.srs | error[unhandled-effect] |
| tests/s2/neg/pat_nested_dotted.srs | a nested pattern is not supported |
| tests/s2/neg/pat_nested_qualified.srs | a nested pattern is not supported |
| tests/s2/neg/pat_nested_unqualified.srs | error[nested-pattern] |
| tests/s2/neg/proto_ambiguous.srs | error[protocol-ambiguous] |
| tests/s2/neg/protocol_gone.srs | error[parse] |
| tests/s2/neg/rt_ptr_user.srs | error[rt-outside-srs] |
| tests/s2/neg/spec_gone.srs | error[parse] |
| tests/s2/neg/srs_name_forge.srs | error[reserved-name] |
| tests/s2/neg/static_extent.srs | error[unhandled-effect] |
| tests/s2/neg/tl_lambda.srs | error[parse] |
| tests/s2/neg/tval_none.srs | error[value-args] |
| tests/s2/neg/word_range.srs | error[int-range] |
