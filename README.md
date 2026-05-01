# nicheR

nicheR is an attempt at "pure R" nicheformer.  See [theislab github](https://github.com/theislab/nicheformer)
for the python code base.  See also the [preprint](https://www.biorxiv.org/content/10.1101/2024.04.15.589472v2)
by Schaar et al.

Code in this repository was negotiated with Claude Sonnet.  The objective is 
to understand whether python interoperation can be avoided without loss
of functionality or performance.

As of May 1 the following steps should succeed.  See the repo issues for work to be done.

- use R 4.6 if possible

- installation
    - `BiocManager::install("vjcitn/nicheR")`

- create a model instance
    - `library(nicheR)`
    - `nn = nicheformer()`
    - `nn`

output should be:
```
An `nn_module` containing 47,115,124 parameters.

── Modules ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
• token_emb: <nn_embedding> #10,416,640 parameters
• pos_emb: <nn_embedding> #768,000 parameters
• transformer: <nn_transformer_encoder> #25,233,408 parameters
• classifier_head: <nn_linear> #10,434,420 parameters
• pooler_head: <nn_sequential> #262,656 parameters
```

- retrieve and cache pretrained weights

    - `getNicheResource("nicheformer_weights.safetensors")` 
        - cache is checked for availability of this weights file
        - if not present
             - file is retrieved from Open Storage Network
             - file is placed in BiocFileCache
    - `library(BiocFileCache)`
    - `ca = BiocFileCache()`
    - `wpa = bfcquery(ca, "nicheformer_weights")$rpath`

- load pretrained weights
 
    - `load_nicheformer_weights(nn, wpa)`

- obtain an example dataset as SingleCellExperiment

   - `example(getNichResource)`
   - note that the example data link provided at github.com/theislab/nicheformer/tree/main/data/spatialcorpus-110M/spatial/examplary-Xenium is an 18GB zip with multiple high resolution tiffs.  A
SingleCellExperiment was extracted with gene quantifications and coordinates;
it was saved using alabaster.  `example(getNicheResource)` will retrieve
