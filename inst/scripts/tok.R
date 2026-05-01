# NOT TESTED

#library(SingleCellExperiment)
#library(Matrix)
#library(RcppCNPy)   # for loading .npy mean vectors

# ------------------------------------------------------------------
# Step 1: Load technology-specific mean vector
# (xenium_mean_script.npy, cosmx_mean_script.npy, iss_mean_script.npy)
# ------------------------------------------------------------------
#load_tech_mean <- function(npy_path) {
#  RcppCNPy::npyLoad(npy_path)  # returns a numeric vector
#}

library(nicheR)
data("xenium_means", package="nicheR")


# ------------------------------------------------------------------
# Step 2: Size factor normalization (target = 10,000 counts per cell)
# Handles both sparse and dense count matrices
# ------------------------------------------------------------------
size_factor_normalize <- function(mat) {
  # mat: genes x cells (standard SCE orientation)
  lib_sizes <- Matrix::colSums(mat)
  lib_sizes[lib_sizes == 0] <- 1  # guard against empty cells
  # scale each cell to 10,000 total counts
  t(t(mat) / lib_sizes * 1e4)
}

# ------------------------------------------------------------------
# Step 3: Align new data to reference gene ordering
# model.h5ad defines the canonical 20,340-gene vocabulary
# Use zellkonverter to read it, then match columns
# ------------------------------------------------------------------
align_to_reference <- function(sce_query, sce_reference) {
  ref_genes  <- rownames(sce_reference)
  query_genes <- rownames(sce_query)
  shared     <- intersect(ref_genes, query_genes)

  # Build a full genes x cells matrix in reference order, zero-filling missing
  n_ref   <- length(ref_genes)
  n_cells <- ncol(sce_query)
  aligned <- Matrix::Matrix(0, nrow = n_ref, ncol = n_cells, sparse = TRUE)
  rownames(aligned) <- ref_genes
  colnames(aligned) <- colnames(sce_query)
  idx <- match(shared, ref_genes)
  aligned[idx, ] <- assay(sce_query, "counts")[shared, ]
  aligned
}

# ------------------------------------------------------------------
# Step 4: Core tokenizer
# For each cell: normalize -> mean-adjust -> rank by expression ->
#                take top context_length genes -> add offset 30
# ------------------------------------------------------------------
tokenize_cell <- function(expr_vec, context_length = 1500L, offset = 30L) {
  # expr_vec: named numeric, already size-factor normalized & mean-adjusted
  nonzero_idx <- which(expr_vec > 0)
  if (length(nonzero_idx) == 0L) {
    return(integer(context_length))  # all-pad token
  }
  # Sort by expression descending, take top context_length
  ranked <- nonzero_idx[order(expr_vec[nonzero_idx], decreasing = TRUE)]
  ranked <- head(ranked, context_length)
  # Gene indices become tokens: 1-based position + offset
  # offset=30 reserves low token IDs for special tokens (CLS, MASK, etc.)
  tokens <- ranked + offset
  # Pad to context_length with 1L (R-native PAD index)
  length(tokens) <- context_length
  tokens[is.na(tokens)] <- 1L
  tokens
}

# ------------------------------------------------------------------
# Step 5: Main tokenize_data function
# Returns integer matrix: cells x context_length
# ------------------------------------------------------------------
tokenize_data <- function(sce,
                          tech_mean,        # numeric vector, length = n_genes
                          context_length = 1500L,
                          offset         = 30L,
                          assay_name     = "counts") {
  mat <- assay(sce, assay_name)               # genes x cells
  mat <- size_factor_normalize(mat)           # normalize per cell

  # Mean-adjust: divide each gene by its technology mean
  # Guard against zero means
  tech_mean[tech_mean == 0] <- 1
  mat <- mat / tech_mean                      # broadcasting over columns

  # Tokenize each cell
  n_cells <- ncol(mat)
  tokens  <- matrix(1L, nrow = n_cells, ncol = context_length)

  for (i in seq_len(n_cells)) {
    tokens[i, ] <- tokenize_cell(mat[, i], context_length, offset)
  }
  rownames(tokens) <- colnames(sce)
  tokens
}

# ------------------------------------------------------------------
# Step 6: Prepend auxiliary tokens (specie / assay / modality)
# These sit at the front of the sequence before gene tokens
# Encoded as integers mapped to the extended vocabulary
# ------------------------------------------------------------------
specie_map  <- c(human = 20341L, mouse = 20342L, other = 20343L)
assay_map   <- c(scRNA = 20344L, spatial = 20345L)   # extend as needed
modality_map <- c(transcriptomics = 20386L)           # etc.

prepend_auxiliary <- function(tokens, specie, assay, modality) {
  aux <- c(specie_map[specie], assay_map[assay], modality_map[modality])
  cbind(
    matrix(aux, nrow = nrow(tokens), ncol = 3L, byrow = TRUE),
    tokens[, seq_len(ncol(tokens) - 3L)]   # trim end to keep total length fixed
  )
}
