# Script R para gerar graficos e tabelas sugeridos em 'montando-graficos.txt'

# 0. Carregar bibliotecas

library(ggplot2)
library(dplyr)
library(readr)
library(scales)

# 1. Ler as tabelas e arquivos de entrada (INPUT)

DIR_BASE <- "../Archaea-Database/"
DIR_SAIDA <- "resultados-R"

if (!dir.exists(DIR_BASE)) {
  stop(paste0("Diretorio '", DIR_BASE, "' nao encontrado."), call. = FALSE)
}

read_my_tsv <- function(param_file) {
  if (file.exists(param_file) == FALSE) { stop("Arquivo ", param_file, " nao encontrado!", call.=FALSE) }
  return(readr::read_tsv(file = param_file, na = c("NULL", "", "NA"), show_col_types = TRUE))
}

# 1) Recuperar genomas e os metadados
orig_assembly <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ORIGINAL-METADATA/ASSEMBLY-METADATA.tsv"))
orig_quality <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ORIGINAL-METADATA/QUALITY-METADATA.tsv"))
orig_sample <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ORIGINAL-METADATA/SAMPLE-METADATA.tsv"))

# 2) Filtragem dos genomas por dados de qualidade pelos metadados do QUALITY-METADATA.tsv 
list_first_filter <- read_my_tsv(file.path(DIR_BASE, "lista-genomas-filtrados.txt"))
therm_label_data <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/THERMOPHILIC-LABELED-METADATA.tsv"))

# 3) Identificacao dos genomas de termofilos
list_therm_only <- read_my_tsv(file.path(DIR_BASE, "lista-genomas-thermophilic.txt"))
therm_only_data <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ONLY-THERMOPHILIC-METADATA.tsv"))

# 4) Filtragem dos genomas com muitos gaps (bases N)
list_few_gaps <- read_my_tsv(file.path(DIR_BASE, "lista-genomas-poucos-gaps.txt"))
contig_gaps_table <- read_my_tsv(file.path(DIR_BASE, "SEQKIT-RESULTS/contagem-gaps-n-por-contig.txt"))

# 5) Filtragem dos genomas pela completude e contaminacao calculados com CheckM2
list_non_checkm2_filter <- read_my_tsv(file.path(DIR_BASE, "CHECKM2-RESULTS/lista_genomas.txt"))
checkm2_quality <- read_my_tsv(file.path(DIR_BASE, "CHECKM2-RESULTS/quality_report.tsv"))

list_checkm2_filter <- read_my_tsv(file.path(DIR_BASE, "lista-genomas-alta-qualidade.txt"))
   
# 6) Busca pela classificacao taxonomica no GTDB
gtdb_tax_table <- read_my_tsv(file.path(DIR_BASE, "TAXONOMY-DIRECTORY/TAXONOMY-TABLE.tsv"))
list_non_classified_tax <- read_my_tsv(file.path(DIR_BASE, "TAXONOMY-DIRECTORY/lista-genomas-nao-classificados.txt"))
   
# 7) Classificacao taxonomica dos genomas remanescentes
ARC_TAX_FILE <- "gtdbtk.ar53.summary.tsv"
BAC_TAX_FILE <- "gtdbtk.bac120.summary.tsv"
archaea_tax <- ""
bacteria_tax <- ""
if (file.exists(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", ARC_TAX_FILE)) == TRUE) {
  archaea_tax <- read_tsv(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", ARC_TAX_FILE))
}
if (file.exists(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", BAC_TAX_FILE)) != 0) {
  bacteria_tax <- read_tsv(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", BAC_TAX_FILE))
}
gtdb_gtdbtk_tax_table <- read_tsv(file.path(DIR_BASE, "TAXONOMY-DIRECTORY/COMPLETE-TAXONOMY-TABLE.tsv"))
   
# 8) Desreplicacao dos genomas
list_rep <- read_tsv(file.path(DIR_BASE, "lista-genomas-representativos.txt"))
tabela_path_rep <- read_tsv(file.path(DIR_BASE, "tabela-dir-representativos.tsv"))

current_assembly <- read_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ASSEMBLY-METADATA.tsv"))
current_quality <- read_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/QUALITY-METADATA.tsv"))
current_sample <- read_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/SAMPLE-METADATA.tsv"))

# 2. Gerando a tabela com o numero de genomas em cada etapa
table_count_genomes <- tibble::tibble(
  etapa = c(
    "1. Total baixado do NCBI",
    "2. Filtro de qualidade inicial",
    "3. Identificacao como Termofilo",
    "4. Filtro por n° de gaps (bases N)",
    "5. Filtro por completude/contaminacao (CheckM2)",
    "6+7. Classificados taxonomicamente (GTDB+GTDB-TK)",
    "8. Genomas representativos (pos-desreplicacao)"
  ), 
  genomas = c(
    nrow(orig_assembly)-1,
    nrow(list_first_filter),
    nrow(list_therm_only),
    nrow(list_few_gaps),
    nrow(list_checkm2_filter),
    nrow(gtdb_gtdbtk_tax_table)-1,
    nrow(list_rep)
  )
)

# 3. Incluindo porcentagens na tabela
table_count_genomes <- table_count_genomes |> mutate(
    pct_do_total = genomas / first(genomas) * 100,
    pct_da_anterior = genomas / lag(genomas, default = first(genomas)) * 100,
    etapa = factor(etapa, levels = rev(etapa))  # preserva ordem no grafico
)
print(table_count_genomes)
 

# 4. Formatando tabela 
tabela_formatada <- table_count_genomes %>%
  mutate(
    Etapa          = as.character(etapa),
    `Genomas restantes` = trimws(format(genomas, big.mark = ".", decimal.mark = ",", scientific = FALSE)),
    `% do total`   = paste0(trimws(format(round(pct_do_total, 1), decimal.mark = ",")), "%"),
    `% da etapa anterior` = paste0(trimws(format(round(pct_da_anterior, 1), decimal.mark = ",")), "%")
  ) %>%
select(Etapa, `Genomas restantes`, `% do total`, `% da etapa anterior`) %>%
arrange(match(Etapa, rev(levels(table_count_genomes$etapa))))

print(tabela_formatada)
  
# 5. Salvar tabela em TSV (para abrir em Excel/planilhas)
write.table(
  tabela_formatada,
  file.path(DIR_SAIDA, "funil_filtragem.tsv"),
  sep = "\t", row.names = FALSE, quote = FALSE, fileEncoding = "UTF-8"
)

# 5.1 Salvar tabela em Markdown (para colar em relatorios/README)
linhas_md <- c(
  paste0("| ", paste(names(tabela_formatada), collapse = " | "), " |"),
  paste0("|", paste(rep("---", ncol(tabela_formatada)), collapse = "|"), "|"),
  apply(tabela_formatada, 1, function(x) paste0("| ", paste(x, collapse = " | "), " |"))
)
writeLines(linhas_md, file.path(DIR_SAIDA, "funil_filtragem.md"))

# 6. Gerando grafico de funil
grafico_funil <- ggplot(table_count_genomes, aes(x = etapa, y = genomas)) +
  geom_col(fill = "#2C7FB8", width = 0.7) +
  geom_text(
    aes(label = paste0(format(genomas, big.mark = ".", decimal.mark = ","), "  (", round(pct_do_total, 1), "%)")),
    hjust = -0.05, size = 3.4
  ) +
  coord_flip(clip = "off") +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.25))
  ) +
  labs(
    title = "Funil de filtragem dos genomas de Archaea",
    subtitle = "Numero de genomas restantes a cada etapa do pipeline",
    x = NULL,
    y = "Numero de genomas"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank()
  )

ggsave(
  file.path(DIR_SAIDA, "funil_filtragem.png"),
  grafico_funil, width = 9, height = 5.5, dpi = 300
)

message("Tabela e grafico salvos em: ", normalizePath(DIR_SAIDA))
  
  
  
  
  
  
# #!/usr/bin/env Rscript

# # =============================================================================
# # Analise de genomas de procariotos termofilicos
# # 01 - Funil de filtragem do pipeline
# #
# # Gera:
# #   - tabela (TSV + Markdown) com o numero de genomas restantes em cada etapa
# #   - grafico de funil (barras horizontais) mostrando a reducao do dataset
# # =============================================================================

# library(ggplot2)
# library(dplyr)
# library(scales)

# # --- 0. Configuracao -------------------------------------------------------

# DIR_SAIDA <- "resultados-R"
# dir.create(DIR_SAIDA, showWarnings = FALSE, recursive = TRUE)

# # Diretorio base onde estao os arquivos do pipeline (ajuste se necessario)
# DIR_BASE <- "Archaea-Database" # fazer a leitura ser na chamada do script: "Archaea-Database" ou "Bacteria-Database"

# # --- 1. Funcoes de contagem --------------------------------------------------
# # Contam os genomas dos arquivos da pipeline

# # Para listas simples (lista-genomas-*.txt): uma linha = um genoma, sem header
# contar_linhas_lista <- function(caminho) {
  # if (!file.exists(caminho)) {
    # warning("Arquivo nao encontrado: ", caminho)
    # return(NA_integer_)
  # }
  # length(readLines(caminho))
# }

# # Para tabelas TSV com header (ex: METADATA, TAXONOMY-TABLE): desconta a 1a linha
# contar_linhas_tsv <- function(caminho) {
  # n <- contar_linhas_lista(caminho)
  # if (is.na(n)) return(NA_integer_)
  # n - 1L
# }

# # --- 2. Dados do funil, lidos diretamente dos arquivos do pipeline ----------

# funil <- tibble::tibble(
  # etapa = c(
    # "1. Recuperados (Archaea)",
    # "2. Filtro de qualidade",
    # "3. Termofilicos",
    # "4. Poucos gaps (bases N)",
    # "5. CheckM2 (completude/contaminacao)",
    # "6+7. Classificados taxonomicamente",
    # "8. Representativos (pos-dereplicacao)"
  # ),
  # genomas = c(
    # contar_linhas_tsv(file.path(DIR_BASE, list"METADATA-DIRECTORY/ORIGINAL-METADATA/ASSEMBLY-METADATA.tsv")),
    # contar_linhas_lista(file.path(DIR_BASE, "lista-genomas-filtrados.txt")),
    # contar_linhas_lista(file.path(DIR_BASE, "lista-genomas-thermophilic.txt")),
    # contar_linhas_lista(file.path(DIR_BASE, "lista-genomas-poucos-gaps.txt")),
    # contar_linhas_lista(file.path(DIR_BASE, "lista-genomas-alta-qualidade.txt")),
    # contar_linhas_tsv(file.path(DIR_BASE, "TAXONOMY-DIRECTORY/COMPLETE-TAXONOMY-TABLE.tsv")),
    # contar_linhas_lista(file.path(DIR_BASE, "lista-genomas-representativos.txt"))
  # )
# )

# # Interrompe cedo se algum arquivo essencial nao foi encontrado -- evita
# # gerar tabela/grafico com etapas faltando (NA) sem o usuario perceber
# if (anyNA(funil$genomas)) {
  # etapas_faltando <- funil$etapa[is.na(funil$genomas)]
  # stop(
    # "Nao foi possivel contar genomas para: ", paste(etapas_faltando, collapse = "; "),
    # "\nConfira o DIR_BASE ('", DIR_BASE, "') e se os arquivos do pipeline existem nesse caminho."
  # )
# }

# # --- 2. Calcular percentuais -------------------------------------------------

# funil <- funil %>%
  # mutate(
    # pct_do_total   = genomas / first(genomas) * 100,
    # pct_da_anterior = genomas / lag(genomas, default = first(genomas)) * 100,
    # etapa = factor(etapa, levels = rev(etapa))  # preserva ordem no grafico
  # )

# # --- 3. Tabela formatada -----------------------------------------------------

# tabela_formatada <- funil %>%
  # mutate(
    # Etapa          = as.character(etapa),
    # `Genomas restantes` = trimws(format(genomas, big.mark = ".", decimal.mark = ",", scientific = FALSE)),
    # `% do total`   = paste0(trimws(format(round(pct_do_total, 1), decimal.mark = ",")), "%"),
    # `% da etapa anterior` = paste0(trimws(format(round(pct_da_anterior, 1), decimal.mark = ",")), "%")
  # ) %>%
  # select(Etapa, `Genomas restantes`, `% do total`, `% da etapa anterior`) %>%
  # arrange(match(Etapa, rev(levels(funil$etapa))))

# print(tabela_formatada)

# # Salvar tabela em TSV (para abrir em Excel/planilhas)
# write.table(
  # tabela_formatada,
  # file.path(DIR_SAIDA, "funil_filtragem.tsv"),
  # sep = "\t", row.names = FALSE, quote = FALSE, fileEncoding = "UTF-8"
# )

# # Salvar tabela em Markdown (para colar em relatorios/README)
# linhas_md <- c(
  # paste0("| ", paste(names(tabela_formatada), collapse = " | "), " |"),
  # paste0("|", paste(rep("---", ncol(tabela_formatada)), collapse = "|"), "|"),
  # apply(tabela_formatada, 1, function(x) paste0("| ", paste(x, collapse = " | "), " |"))
# )
# writeLines(linhas_md, file.path(DIR_SAIDA, "funil_filtragem.md"))

# # --- 4. Grafico de funil ------------------------------------------------------

# grafico_funil <- ggplot(funil, aes(x = etapa, y = genomas)) +
  # geom_col(fill = "#2C7FB8", width = 0.7) +
  # geom_text(
    # aes(label = paste0(format(genomas, big.mark = ".", decimal.mark = ","), "  (", round(pct_do_total, 1), "%)")),
    # hjust = -0.05, size = 3.4
  # ) +
  # coord_flip(clip = "off") +
  # scale_y_continuous(
    # labels = label_number(big.mark = ".", decimal.mark = ","),
    # expand = expansion(mult = c(0, 0.25))
  # ) +
  # labs(
    # title = "Funil de filtragem dos genomas de Archaea",
    # subtitle = "Numero de genomas restantes a cada etapa do pipeline",
    # x = NULL,
    # y = "Numero de genomas"
  # ) +
  # theme_minimal(base_size = 12) +
  # theme(
    # plot.title = element_text(face = "bold"),
    # panel.grid.major.y = element_blank(),
    # panel.grid.minor = element_blank()
  # )

# ggsave(
  # file.path(DIR_SAIDA, "funil_filtragem.png"),
  # grafico_funil, width = 9, height = 5.5, dpi = 300
# )

# message("Tabela e grafico salvos em: ", normalizePath(DIR_SAIDA))
