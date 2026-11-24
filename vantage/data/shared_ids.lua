-- Ids several modules read, written once. Nothing writes into these tables.
return {
    -- The jobs on Phoenix by job id, 1 to 18 (Phoenix data/enums/job.yaml :12-29).
    jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP' },
    -- Copy Image (66) shows its shadows as icons 444, 445 and 446 (Phoenix data/status_effects.yaml :617, :4007, :4016
    -- and :4025), and every copy leaves the tracker as 66, so each of them reads as 66.
    copy_image = { [444] = 66, [445] = 66, [446] = 66 },
};
