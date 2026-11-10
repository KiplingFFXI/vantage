-- Every settings key an export could hold at 1.0 and since, by the table that holds it ('' is the top, '[]' a list's items).
-- Written from ui/defaults.make(). Add a key here when one is added. A key on this list stays in fresh settings:
-- share.read refuses a string that holds a key they don't have, so a string made with it would stop pasting.
return {
    [''] = 'active_profile alerts chat_colors diagnostics durations edit_mode effect_filters enabled'
        .. ' job_profiles overhead panels party_cooldowns party_ui pet preview ready_pulse recast_display recast_tints'
        .. ' rolls shared_layout shared_scope style tracking visibility watch_ids window window_style',
    ['alerts'] = 'enabled max_notices muted notice_anchor notice_conditions notice_height notice_locked'
        .. ' notice_width notice_x notice_y quiet_events rules volume',
    ['alerts.notice_anchor'] = 'align dx dy element gap offset point side to',
    ['alerts.notice_conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['chat_colors'] = 'replies tag_brackets tag_word',
    ['diagnostics'] = 'max_entries record',
    ['durations'] = 'learn learn_samples learned overrides',
    ['edit_mode'] = 'grid grid_displays grid_mode show_grid snap_chat snap_distance snap_elements snap_grid snap_party'
        .. ' snap_screen',
    ['effect_filters'] = 'enabled rules',
    ['overhead'] = 'blink_icons blink_seconds camera conditions countdown_bold countdown_color countdown_outline'
        .. ' countdown_outline_color countdown_shadow dispel_color dispel_glow dispel_light distance_cap enabled'
        .. ' fade_alpha fade_start head hide_in_cities layout max_units preview size small_icon_inside_px types units',
    ['overhead.camera'] = 'capture hold_ms max_distance scene_index',
    ['overhead.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['overhead.head'] = 'chair_factor default_height default_hitbox heights mob_height_base mob_height_max'
        .. ' mob_height_min mob_height_per_hitbox mounted_base mounted_factor offsets race_heights sit_factor sizes',
    ['overhead.layout'] = 'cc_scale gap icon_gap line_gap name_cap name_height placement split_gap target_cap'
        .. ' target_height',
    ['overhead.size'] = 'alpha base beta max_px min_px ref_depth ref_hitbox s_max s_min target_scale',
    ['overhead.types'] = 'alliance mob other other_pet party pet self',
    ['overhead.types.alliance'] = 'buffs_mine_only cleanse_light countdown debuffs_party_only exclude include kinds'
        .. ' layout limit line_buffs line_debuffs mine_only name_lift screen_x screen_y shared_rules'
        .. ' show_barspells show_copy_image show_food show_protect_shell show_rolls show_signet show_songs'
        .. ' show_stances show_third_eye size_scale split_buffs split_debuffs swap_lines swap_sides world_offset',
    ['overhead.types.mob'] = 'buffs_mine_only cc_slot countdown debuffs_party_only exclude include kinds'
        .. ' layout limit line_buffs line_debuffs mine_only name_lift screen_x screen_y shared_rules'
        .. ' show_barspells show_copy_image show_food show_protect_shell show_rolls show_signet show_songs'
        .. ' show_stances show_third_eye size_scale split_buffs split_debuffs swap_lines swap_sides world_offset',
    ['overhead.types.other'] = 'buffs_mine_only countdown debuffs_party_only exclude include kinds'
        .. ' layout limit line_buffs line_debuffs mine_only name_lift screen_x screen_y shared_rules'
        .. ' show_barspells show_food show_protect_shell show_rolls show_signet show_songs show_stances'
        .. ' size_scale split_buffs split_debuffs swap_lines swap_sides world_offset',
    ['overhead.types.other_pet'] = 'buffs_mine_only countdown debuffs_party_only exclude include kinds'
        .. ' layout limit line_buffs line_debuffs mine_only name_lift screen_x screen_y shared_rules'
        .. ' show_barspells show_food show_protect_shell show_rolls show_signet show_songs show_stances'
        .. ' size_scale split_buffs split_debuffs swap_lines swap_sides world_offset',
    ['overhead.types.party'] = 'buffs_mine_only cleanse_light countdown debuffs_party_only exclude include kinds'
        .. ' layout limit line_buffs line_debuffs mine_only name_lift screen_x screen_y shared_rules'
        .. ' show_barspells show_copy_image show_food show_protect_shell show_rolls show_signet show_songs'
        .. ' show_stances show_third_eye size_scale split_buffs split_debuffs swap_lines swap_sides world_offset',
    ['overhead.types.pet'] = 'buffs_mine_only countdown debuffs_party_only exclude include kinds layout'
        .. ' limit line_buffs line_debuffs mine_only name_lift screen_x screen_y shared_rules'
        .. ' show_barspells show_food show_protect_shell show_rolls show_signet show_songs show_stances'
        .. ' size_scale split_buffs split_debuffs swap_lines swap_sides world_offset',
    ['overhead.types.self'] = 'buffs_mine_only cleanse_light countdown debuffs_party_only exclude include kinds layout'
        .. ' limit line_buffs line_debuffs mine_only name_lift screen_x screen_y shared_rules'
        .. ' show_barspells show_copy_image show_food show_protect_shell show_rolls show_signet show_songs'
        .. ' show_stances show_third_eye size_scale split_buffs split_debuffs swap_lines swap_sides world_offset',
    ['overhead.units'] = 'alliance claimed debuffed other other_pet party pet self subtarget target watched',
    ['panels'] = 'ability_recasts item_recasts party recasts self_buffs self_debuffs spell_recasts target watch',
    ['panels.ability_recasts'] = 'alignment anchor auto_height auto_width bar_style bar_thickness box colors conditions'
        .. ' countdown_bold countdown_outline countdown_outline_color countdown_shadow direction dock_match_width'
        .. ' effect_colors empty enabled exclude field_alignments field_colors field_dividers field_labels'
        .. ' field_newlines field_order field_priority fill_direction filter gradient group_by groups growth'
        .. ' height_limit horizon icon_countdown_gap icon_countdown_position icon_countdown_size include item_width'
        .. ' known_only label_position label_separator labels locked max_rows max_width members min_width mine_only'
        .. ' mode order pinned priority_overflow row_height separator show_elapsed show_fill show_heading show_icon'
        .. ' show_name show_source show_target show_text show_time show_total sort stack_direction title'
        .. ' warning_enabled warning_mark warning_seconds width wrap x y',
    ['panels.ability_recasts.anchor'] = 'align dx dy element gap offset point side to',
    ['panels.ability_recasts.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs'
        .. ' zones',
    ['panels.item_recasts'] = 'alignment anchor auto_height auto_width bar_style bar_thickness box colors conditions'
        .. ' countdown_bold countdown_outline countdown_outline_color countdown_shadow direction dock_match_width'
        .. ' effect_colors empty enabled exclude field_alignments field_colors field_dividers field_labels'
        .. ' field_newlines field_order field_priority fill_direction filter gradient group_by groups growth'
        .. ' height_limit horizon icon_countdown_gap icon_countdown_position icon_countdown_size include item_width'
        .. ' known_only label_position label_separator labels locked max_rows max_width members min_width mine_only'
        .. ' mode order pinned priority_overflow row_height separator show_elapsed show_fill show_heading show_icon'
        .. ' show_name show_source show_target show_text show_time show_total sort stack_direction title'
        .. ' warning_enabled warning_mark warning_seconds width wrap x y',
    ['panels.item_recasts.anchor'] = 'align dx dy element gap offset point side to',
    ['panels.item_recasts.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['panels.party'] = 'abilities_only alignment anchor auto_height auto_width bar_style bar_thickness blink_icons'
        .. ' blink_seconds box colors conditions countdown_bold countdown_outline countdown_outline_color'
        .. ' countdown_shadow direction'
        .. ' dispel_color dispel_glow dispel_light dock_match_width effect_colors empty enabled exclude'
        .. ' field_alignments field_colors field_dividers field_labels field_newlines field_order field_priority'
        .. ' fill_direction filter gradient group_by groups growth height_limit horizon icon_countdown_gap'
        .. ' icon_countdown_position icon_countdown_size include item_width known_only label_position label_separator'
        .. ' labels locked max_rows max_width members min_width mine_only mode order pinned priority_overflow'
        .. ' row_height separator show_elapsed show_fill show_heading show_icon show_name show_source show_target'
        .. ' show_text show_time show_total sort stack_direction title warning_enabled warning_mark warning_seconds'
        .. ' width wrap x y',
    ['panels.party.anchor'] = 'align dx dy element gap offset point side to',
    ['panels.party.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['panels.recasts'] = 'alignment anchor auto_height auto_width bar_style bar_thickness box colors conditions'
        .. ' countdown_bold countdown_outline countdown_outline_color countdown_shadow direction dock_match_width'
        .. ' effect_colors empty enabled exclude field_alignments field_colors field_dividers field_labels'
        .. ' field_newlines field_order field_priority fill_direction filter gradient group_by groups growth'
        .. ' height_limit horizon icon_countdown_gap icon_countdown_position icon_countdown_size include item_width'
        .. ' known_only label_position label_separator labels locked max_rows max_width members min_width mine_only'
        .. ' mode order pinned priority_overflow recast_categories row_height separator show_elapsed show_fill'
        .. ' show_heading show_icon show_name show_source show_target show_text show_time show_total sort'
        .. ' stack_direction title warning_enabled warning_mark warning_seconds width wrap x y',
    ['panels.recasts.anchor'] = 'align dx dy element gap offset point side to',
    ['panels.recasts.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['panels.recasts.recast_categories'] = 'ability item spell',
    ['panels.self_buffs'] = 'alignment anchor auto_height auto_width bar_style bar_thickness blink_icons blink_seconds'
        .. ' box colors conditions countdown_bold countdown_outline countdown_outline_color countdown_shadow direction'
        .. ' dock_match_width effect_colors empty enabled exclude field_alignments field_colors field_dividers'
        .. ' field_labels field_newlines field_order field_priority fill_direction filter gradient group_by groups'
        .. ' growth height_limit horizon icon_countdown_gap icon_countdown_position icon_countdown_size include'
        .. ' item_width known_only label_position label_separator labels locked max_rows max_width members min_width'
        .. ' mine_only mode order pinned priority_overflow row_height separator show_elapsed show_fill show_heading'
        .. ' show_icon show_name show_source show_target show_text show_time show_total sort stack_direction title'
        .. ' warning_enabled warning_mark warning_seconds width wrap x y',
    ['panels.self_buffs.anchor'] = 'align dx dy element gap offset point side to',
    ['panels.self_buffs.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['panels.self_debuffs'] = 'alignment anchor auto_height auto_width bar_style bar_thickness blink_icons'
        .. ' blink_seconds box colors conditions countdown_bold countdown_outline countdown_outline_color'
        .. ' countdown_shadow direction dispel_color dispel_glow dispel_light dock_match_width effect_colors empty'
        .. ' enabled exclude field_alignments field_colors field_dividers field_labels field_newlines field_order'
        .. ' field_priority fill_direction filter gradient group_by groups growth height_limit horizon'
        .. ' icon_countdown_gap icon_countdown_position icon_countdown_size include item_width known_only'
        .. ' label_position label_separator labels locked max_rows max_width members min_width mine_only mode order'
        .. ' pinned priority_overflow row_height separator show_elapsed show_fill show_heading show_icon show_name'
        .. ' show_source show_target show_text show_time show_total sort stack_direction title warning_enabled'
        .. ' warning_mark warning_seconds width wrap x y',
    ['panels.self_debuffs.anchor'] = 'align dx dy element gap offset point side to',
    ['panels.self_debuffs.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['panels.spell_recasts'] = 'alignment anchor auto_height auto_width bar_style bar_thickness box colors conditions'
        .. ' countdown_bold countdown_outline countdown_outline_color countdown_shadow direction dock_match_width'
        .. ' effect_colors empty enabled exclude field_alignments field_colors field_dividers field_labels'
        .. ' field_newlines field_order field_priority fill_direction filter gradient group_by groups growth'
        .. ' height_limit horizon icon_countdown_gap icon_countdown_position icon_countdown_size include item_width'
        .. ' known_only label_position label_separator labels locked max_rows max_width members min_width mine_only'
        .. ' mode order pinned priority_overflow row_height separator show_elapsed show_fill show_heading show_icon'
        .. ' show_name show_source show_target show_text show_time show_total sort stack_direction title'
        .. ' warning_enabled warning_mark warning_seconds width wrap x y',
    ['panels.spell_recasts.anchor'] = 'align dx dy element gap offset point side to',
    ['panels.spell_recasts.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs'
        .. ' zones',
    ['panels.target'] = 'alignment anchor auto_height auto_width bar_style bar_thickness blink_icons blink_seconds box'
        .. ' colors conditions countdown_bold countdown_outline countdown_outline_color countdown_shadow direction'
        .. ' dispel_color dispel_glow dispel_light dock_match_width effect_colors empty enabled exclude'
        .. ' field_alignments field_colors field_dividers field_labels field_newlines field_order field_priority'
        .. ' fill_direction filter gradient group_by groups growth height_limit horizon icon_countdown_gap'
        .. ' icon_countdown_position icon_countdown_size include item_width known_only label_position label_separator'
        .. ' labels locked max_rows max_width members min_width mine_only mode order pinned priority_overflow'
        .. ' row_height separator show_elapsed show_fill show_heading show_icon show_name show_source show_target'
        .. ' show_text show_time show_total sort stack_direction title warning_enabled warning_mark warning_seconds'
        .. ' width wrap x y',
    ['panels.target.anchor'] = 'align dx dy element gap offset point side to',
    ['panels.target.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['panels.watch'] = 'alignment anchor auto_height auto_width bar_style bar_thickness blink_icons blink_seconds box'
        .. ' colors conditions countdown_bold countdown_outline countdown_outline_color countdown_shadow direction'
        .. ' dispel_color dispel_glow dispel_light dock_match_width effect_colors empty enabled exclude'
        .. ' field_alignments field_colors field_dividers field_labels field_newlines field_order field_priority'
        .. ' fill_direction filter gradient group_by groups growth height_limit horizon icon_countdown_gap'
        .. ' icon_countdown_position icon_countdown_size include item_width known_only label_position label_separator'
        .. ' labels list_debuffed locked max_rows max_width members min_width mine_only mode order pinned'
        .. ' priority_overflow row_height separator show_elapsed show_fill show_heading show_icon show_name show_source'
        .. ' show_target show_text show_time show_total sort stack_direction title warning_enabled warning_mark'
        .. ' warning_seconds width wrap x y',
    ['panels.watch.anchor'] = 'align dx dy element gap offset point side to',
    ['panels.watch.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['party_cooldowns'] = 'enabled ignore list overhead preview strips',
    ['party_cooldowns.list'] = 'abilities anchor conditions enabled height jobs locked max_rows show_heading sort'
        .. ' width x y',
    ['party_cooldowns.list.anchor'] = 'align dx dy element gap offset point side to',
    ['party_cooldowns.list.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs'
        .. ' zones',
    ['party_ui'] = 'conditions effects enabled groups include_self locked name_display name_length native preview'
        .. ' show_solo strips style',
    ['party_ui.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['party_ui.effects'] = 'abilities_only blink_icons blink_seconds cleanse_light countdown_bold countdown_outline'
        .. ' countdown_outline_color countdown_shadow exclude fit_all growth icon_countdown_gap icon_countdown_position'
        .. ' icon_countdown_size icon_size include kind max pinned separate show_copy_image show_third_eye sort timers',
    ['party_ui.groups.[]'] = 'detached_height detached_width detached_x detached_y native_detached native_side'
        .. ' native_x native_y order',
    ['party_ui.native'] = 'gap side snap width',
    ['party_ui.strips'] = 'alliance1 alliance2 party',
    ['party_ui.style'] = 'icon_art opacity',
    ['pet'] = 'anchor blink_icons blink_seconds conditions countdown_bold countdown_outline countdown_outline_color'
        .. ' countdown_shadow effects_as enabled exclude height hp_color include kinds locked max_effects max_recasts'
        .. ' mp_color preview shared_rules show_charm show_countdowns show_effects show_maneuvers show_recasts'
        .. ' show_vitals tp_color width x y',
    ['pet.anchor'] = 'align dx dy element gap offset point side to',
    ['pet.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['ready_pulse'] = 'anchor color conditions early enabled ignore length locked min_seconds size spot x y',
    ['ready_pulse.anchor'] = 'align dx dy element gap offset point side to',
    ['ready_pulse.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['recast_tints'] = 'ability_lock ability_lock_color mp mp_color spell_lock spell_lock_color',
    ['rolls'] = 'anchor conditions countdown_bold countdown_outline countdown_outline_color countdown_shadow enabled'
        .. ' height locked lucky_color max_rolls missed_color preview show_effect show_heading show_members'
        .. ' show_numbers show_odds unlucky_color width x y',
    ['rolls.anchor'] = 'align dx dy element gap offset point side to',
    ['rolls.conditions'] = 'engaged group level_max level_min level_sync main_jobs pet sub_jobs zones',
    ['style'] = 'accent_color background background_color bar_height border border_color buff_color debuff_color'
        .. ' detail_color estimate_color font font_size gap gauge_art hover icon_art icon_size label_color minimal'
        .. ' opacity outline_color recast_icon_art recast_icon_source rounding scale status_time_color text_color'
        .. ' text_outline text_shadow theme title_color title_size track_color unknown_color value_color warning_color'
        .. ' window_type',
    ['tracking'] = 'follow_subtarget max_entities stale_seconds',
    ['visibility'] = 'hide_events hide_map hide_typing hide_ui',
    ['window'] = 'height open peek sections tab width x y',
    ['window_style'] = 'font_size',
};
