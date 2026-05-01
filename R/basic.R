#' BERT-style masking (mirrors _utils.py::complete_masking)
#' Token index 1 is reserved as MASK; real gene tokens start at 2
#' @import torch
#' @param tokens any
#' @param masking_p numeric
#' @param n_tokens integer
#' @param mask_token integer
#' @export
complete_masking <- function(tokens, masking_p = 0.15, n_tokens = 20340L,
                              mask_token = 1L) {
  mask   <- torch_bernoulli(torch_full_like(tokens$float(), masking_p))$bool()
  labels <- torch_where(mask, tokens, torch_full_like(tokens, -100L))

  replace_mask  <- torch_bernoulli(torch_full_like(tokens$float(), 0.8))$bool() & mask
  random_mask   <- torch_bernoulli(torch_full_like(tokens$float(), 0.5))$bool() &
                   mask & !replace_mask

  tokens <- torch_where(replace_mask, torch_full_like(tokens, mask_token), tokens)
  random_tokens <- torch_randint(2L, n_tokens, tokens$shape, dtype = torch_long())
  tokens <- torch_where(random_mask, random_tokens, tokens)

  list(tokens = tokens, labels = labels)
}

#' Sinusoidal positional encoding (used when learnable_pe = FALSE)
#' @param context_length numeric
#' @param dim_model numeric
sinusoidal_pe <- function(context_length, dim_model) {
  pe  <- torch_zeros(context_length, dim_model)
  pos <- torch_arange(1, context_length)$unsqueeze(2)$float()
# FIXME: hardcoded constants
  div <- torch_exp(
    torch_arange(1, dim_model / 2)$float() * (-log(10000) / dim_model)
  )
  pe[, seq(1, dim_model - 1, 2)] <- torch_sin(pos * div)
  pe[, seq(2, dim_model,     2)] <- torch_cos(pos * div)
  pe$unsqueeze(1)   # (context_length, 1, dim_model)
}


#' the nicheformer interface
#' @param dim_model integer
#' @param nheads integer  
#' @param dim_feedforward integer
#' @param nlayers integer
#' @param dropout numeric
#' @param masking_p numeric
#' @param n_tokens integer
#' @param total_tokens integer 
#' @param context_length integer 
#' @param learnable_pe logical
#' @export
nicheformer <- function(
    dim_model       = 512L,
    nheads          = 16L,
    dim_feedforward = 1024L,
    nlayers         = 12L,
    dropout         = 0.0,
    masking_p       = 0.15,
    n_tokens        = 20340L,
    total_tokens    = 20345L,
    context_length  = 1500L,
    learnable_pe    = TRUE
) {
  net <- nn_module(
    classname = "Nicheformer",
    initialize = function(dim_model, nheads, dim_feedforward, nlayers,
                          dropout, masking_p, n_tokens, total_tokens,
                          context_length, learnable_pe) {
      self$masking_p      <- masking_p
      self$n_tokens       <- n_tokens
      self$context_length <- context_length
      self$dim_model      <- dim_model
      self$learnable_pe   <- learnable_pe

      # Use total_tokens directly — no recomputation from aux flags
      self$token_emb <- nn_embedding(total_tokens, dim_model, padding_idx = 1L)

      if (learnable_pe) {
        self$pos_emb <- nn_embedding(context_length, dim_model)
      } else {
        self$register_buffer(
          "pos_emb_fixed",
          sinusoidal_pe(context_length, dim_model)
        )
      }

      encoder_layer <- nn_transformer_encoder_layer(
        d_model         = dim_model,
        nhead           = nheads,
        dim_feedforward = dim_feedforward,
        dropout         = dropout,
        activation      = "gelu",
        batch_first     = TRUE
      )
      self$transformer <- nn_transformer_encoder(
        encoder_layer = encoder_layer,
        num_layers    = nlayers
        # no norm — not present in checkpoint
      )

      self$classifier_head <- nn_linear(dim_model, n_tokens)  # FIXED
      self$pooler_head <- nn_sequential(
        nn_linear(dim_model, dim_model),
        nn_tanh()
      )
    },
     forward = function(tokens, apply_masking = TRUE) {
    labels <- NULL
    if (apply_masking) {
      masked <- complete_masking(tokens, self$masking_p, self$n_tokens)
      tokens <- masked$tokens
      labels <- masked$labels
    }

    # Token embeddings
    x <- self$token_emb(tokens)

    # Positional embeddings (1-based arange)
    seq_len <- tokens$shape[2]
    if (self$learnable_pe) {
      pos <- torch_arange(1L, seq_len, dtype = torch_long(),
                          device = tokens$device)
      x <- x + self$pos_emb(pos)$unsqueeze(1)
    } else {
      x <- x + self$pos_emb_fixed[1:seq_len, , ]$transpose(1, 2)
    }
  
    # Transformer encoder
    encoded <- self$transformer(x)

    # MLM logits over full vocab
    logits <- self$classifier_head(encoded)

    # CLS token is at position 1 (first token in sequence)
    cls_embedding <- self$pooler_head(encoded[ , 1, ])
    
    list(logits = logits, cls_embedding = cls_embedding, labels = labels)
  },   # end forward
  get_embeddings = function(tokens) {
    out <- self$forward(tokens, apply_masking = FALSE)
    out$cls_embedding   
  } 
  )

  net$new(
    dim_model       = dim_model,
    nheads          = nheads,
    dim_feedforward = dim_feedforward,
    nlayers         = nlayers,
    dropout         = dropout,
    masking_p       = masking_p,
    n_tokens        = n_tokens,
    total_tokens    = total_tokens,
    context_length  = context_length,
    learnable_pe    = learnable_pe
  )
}

#' Load pretrained Nicheformer weights from a safetensors file
#' @import safetensors
#' @param model A \code{nicheformer} model instance
#' @param path Path to the safetensors weights file
#' @return The model with loaded weights, set to eval mode
#' @examples
#' nn = nicheformer()
#' nn$state_dict()[["token_emb.weight"]]$std()$item() # S.D. of all elements in tensor
#' if (nchar(wpa <- Sys.getenv("LOCAL_NICHE_WEIGHTS"))>0) {
#' nicheformer_load_weights(nn, wpa)  # will print
#' nn$state_dict()[["token_emb.weight"]]$std()$item()  # should be smaller than previous
#' }
#' @export
nicheformer_load_weights <- function(model, path) {
  ss <- safetensors::safe_load_file(path, framework = "torch")

  remap_keys <- function(py_keys) {
    sapply(py_keys, function(k) {
      if (grepl("^encoder_layer\\.", k)) return(NA_character_)  # template, skip
      if (grepl("^cls_head\\.",      k)) return(NA_character_)  # finetune head, skip
      k <- sub("^embeddings\\.",           "token_emb.",          k)
      k <- sub("^positional_embedding\\.", "pos_emb.",            k)
      k <- sub("^encoder\\.layers\\.",     "transformer.layers.", k)
      k <- sub("^pooler_head\\.",          "pooler_head.0.",      k)
      k
    }, USE.NAMES = FALSE)
  }

  py_keys       <- names(ss)
  r_keys_mapped <- remap_keys(py_keys)
  keep          <- !is.na(r_keys_mapped)
  ss_filtered   <- ss[keep]
  names(ss_filtered) <- r_keys_mapped[keep]

  # Validate before loading
  only_in_r  <- setdiff(names(model$state_dict()), names(ss_filtered))
  only_in_py <- setdiff(names(ss_filtered), names(model$state_dict()))
  if (length(only_in_r) > 0)
    warning("Keys in R model missing from checkpoint: ",
            paste(only_in_r, collapse = ", "))
  if (length(only_in_py) > 0)
    warning("Keys in checkpoint not in R model: ",
            paste(only_in_py, collapse = ", "))

  model$load_state_dict(ss_filtered)
  model$eval()
  invisible(model)
}
