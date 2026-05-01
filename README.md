# nicheR

nicheR is an attempt at "pure R" nicheformer

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
    - `library(BiocFileCache)`
    - `ca = BiocFileCache()`
    - `wpa = bfcquery(ca, "nicheformer_weights")$rpath`

- load pretrained weights
 
    - `load_nicheformer_weights(nn, wpa)`

