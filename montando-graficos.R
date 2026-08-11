# Script R para gerar graficos e tabelas sugeridos em 'montando-graficos.txt'

# 0. Carregar bibliotecas

library(ggplot2)
library(dplyr)
library(readr)
library(scales)
library(janitor)
library(viridis)

# 1. Ler as tabelas e arquivos de entrada (INPUT)

DIR_BASE <- "../Archaea-Database/"
DIR_SAIDA <- "resultados-R"

if (!dir.exists(DIR_BASE)) {
  stop(paste0("Diretorio '", DIR_BASE, "' nao encontrado."), call. = FALSE)
}

read_my_tsv <- function(param_file) {
  if (file.exists(param_file) == FALSE) { stop("Arquivo ", param_file, " nao encontrado!", call.=FALSE) }
  return(readr::read_tsv(
  file = param_file,
  na = c("NULL", "", "NA"), 
  name_repair = janitor::make_clean_names,
  show_col_types = TRUE))
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
  archaea_tax <- read_my_tsv(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", ARC_TAX_FILE))
}
if (file.exists(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", BAC_TAX_FILE)) != 0) {
  bacteria_tax <- read_my_tsv(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", BAC_TAX_FILE))
}
gtdb_gtdbtk_tax_table <- read_my_tsv(file.path(DIR_BASE, "TAXONOMY-DIRECTORY/COMPLETE-TAXONOMY-TABLE.tsv"))
   
# 8) Desreplicacao dos genomas
list_rep <- read_my_tsv(file.path(DIR_BASE, "lista-genomas-representativos.txt"))
tabela_path_rep <- read_my_tsv(file.path(DIR_BASE, "tabela-dir-representativos.tsv"))

current_assembly <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ASSEMBLY-METADATA.tsv"))
current_quality <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/QUALITY-METADATA.tsv"))
current_sample <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/SAMPLE-METADATA.tsv"))



# ================= TABELA DE CONTAGEM =========================


# 1. Criando a tabela com o numero de genomas em cada etapa
table_count_genomes <- tibble::tibble(
  etapa = c(
    "1. Total baixado do NCBI",
    "2. Filtro de qualidade inicial",
    "3. Identificacao como Termofilo",
    "4. Filtro por n° de gaps (bases N)",
    "5. Filtro por completude/contaminacao",
    "6+7. Classificados taxonomicamente",
    "8. Genomas representativos"
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

# 2. Incluindo porcentagens na tabela
table_count_genomes <- table_count_genomes |> mutate(
    pct_do_total = genomas / first(genomas) * 100,
    pct_da_anterior = genomas / lag(genomas, default = first(genomas)) * 100,
    etapa = factor(etapa, levels = rev(etapa))  # preserva ordem no grafico
)
print(table_count_genomes)
 

# 3. Formatando tabela 
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
  
# 4. Salvar tabela em TSV (para abrir em Excel/planilhas)
write.table(
  tabela_formatada,
  file.path(DIR_SAIDA, "funil_filtragem.tsv"),
  sep = "\t", row.names = FALSE, quote = FALSE, fileEncoding = "UTF-8"
)

# 4.1 Salvar tabela em Markdown (para colar em relatorios/README)
linhas_md <- c(
  paste0("| ", paste(names(tabela_formatada), collapse = " | "), " |"),
  paste0("|", paste(rep("---", ncol(tabela_formatada)), collapse = "|"), "|"),
  apply(tabela_formatada, 1, function(x) paste0("| ", paste(x, collapse = " | "), " |"))
)
writeLines(linhas_md, file.path(DIR_SAIDA, "funil_filtragem.md"))

# 5. Gerando grafico de funil
grafico_barra_contagem <- ggplot(table_count_genomes, aes(x = etapa, y = genomas)) +
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
  grafico_barra_contagem, width = 9, height = 5.5, dpi = 300
)

message("Tabela e grafico salvos em: ", normalizePath(DIR_SAIDA))

# ================= GRAFICOS DE BOXPLOT =========================


# ================= GRAFICOS DE VIOLINO =========================

# # Fazer grafico de violino e boxplot para variaveis numericas continuas, como:
# # orig_quality
# # current_quality # same str as orig_quality
# # > colnames(orig_quality)
# ###[1] "assembly_accession"
  # [2] "assembly_stats_atgc_count"
  # [3] "assembly_stats_contig_l50"
  # [4] "assembly_stats_contig_n50"
  # [5] "assembly_stats_gaps_between_scaffolds_count"
  # [6] "assembly_stats_gc_percent"
  # [7] "assembly_stats_genome_coverage"
  # [8] "assembly_stats_number_of_component_sequences"
  # [9] "assembly_stats_number_of_contigs"
  # [10] "assembly_stats_number_of_scaffolds"
  # [11] "assembly_stats_scaffold_l50"
  # [12] "assembly_stats_scaffold_n50"
  # [13] "assembly_stats_total_sequence_length"
  # [14] "assembly_stats_total_ungapped_length"
  # ###[15] "check_m_completeness"
  # ###[16] "check_m_contamination"

# # checkm2_quality
# # > colnames(checkm2_quality)
  # ### [1] "name"                    
  # [2] "completeness"
  # [3] "contamination"           
  # ### [4] "completeness_model_used"
  # ###[5] "translation_table_used"  
  # [6] "coding_density"
  # [7] "contig_n50"              
  # [8] "average_gene_length"
  # [9] "genome_size"             
  # [10] "gc_content"
  # [11] "total_coding_sequences"  
  # [12] "total_contigs"
  # [13] "max_contig_length"       
  # ###[14] "additional_notes"
  
 # =============================================================================
# Violinos - comparacao de distribuicoes
# (pacotes ggplot2, dplyr, hrbrthemes e viridis ja carregados;
#  tibbles orig_quality, current_quality e checkm2_quality ja criados;
#  DIR_SAIDA ja definido, ex: DIR_SAIDA <- "figuras/qualidade")
# =============================================================================

library(hrbrthemes)
library(viridis)
# -----------------------------------------------------------------------
# 1) orig_quality x current_quality - um violino por coluna numerica
# -----------------------------------------------------------------------

cols_quality <- c(
  "assembly_stats_atgc_count",
  "assembly_stats_contig_l50",
  "assembly_stats_contig_n50",
  # "assembly_stats_gaps_between_scaffolds_count",  # ignorada por enquanto
  "assembly_stats_gc_percent",
  "assembly_stats_genome_coverage",
  "assembly_stats_number_of_component_sequences",
  "assembly_stats_number_of_contigs",
  "assembly_stats_number_of_scaffolds",
  "assembly_stats_scaffold_l50",
  "assembly_stats_scaffold_n50",
  "assembly_stats_total_sequence_length",
  "assembly_stats_total_ungapped_length"
)

for (col in cols_quality) {

  data <- rbind(
    data.frame(name = "Original", value = as.numeric(orig_quality[[col]])),
    data.frame(name = "Atual",    value = as.numeric(current_quality[[col]]))
  )
  data <- data[!is.na(data$value), ]

  sample_size <- data %>% group_by(name) %>% summarize(num = n())

  p <- data %>%
    left_join(sample_size) %>%
    mutate(myaxis = paste0(name, "\n", "n=", num)) %>%
    ggplot(aes(x = myaxis, y = value, fill = name)) +
      geom_violin(width = 1.4) +
      geom_boxplot(width = 0.1, color = "grey", alpha = 0.2) +
      scale_fill_viridis(discrete = TRUE) +
      theme_ipsum(base_family = "sans") +
      theme(
        legend.position = "none",
        plot.title = element_text(size = 11)
      ) +
      ggtitle(col) +
      xlab("")

  print(p)

  ggsave(
    file.path(DIR_SAIDA, paste0("violino_", col, ".png")),
    p, width = 9, height = 5.5, dpi = 300
  )
}

message("Graficos de orig_quality x current_quality salvos em: ", normalizePath(DIR_SAIDA))

# -----------------------------------------------------------------------
# 2) checkm2_quality - completude x contaminacao, lado a lado
# -----------------------------------------------------------------------

data <- rbind(
  data.frame(name = "Completude",   value = as.numeric(checkm2_quality$completeness)),
  data.frame(name = "Contaminacao", value = as.numeric(checkm2_quality$contamination))
)
data <- data[!is.na(data$value), ]

sample_size <- data %>% group_by(name) %>% summarize(num = n())

grafico_checkm2_qc <- data %>%
  left_join(sample_size) %>%
  mutate(myaxis = paste0(name, "\n", "n=", num)) %>%
  ggplot(aes(x = myaxis, y = value, fill = name)) +
    geom_violin(width = 1.4) +
    geom_boxplot(width = 0.1, color = "grey", alpha = 0.2) +
    scale_fill_viridis(discrete = TRUE) +
    theme_ipsum(base_family = "sans") +
    theme(
      legend.position = "none",
      plot.title = element_text(size = 11)
    ) +
    ggtitle("CheckM2: Completude x Contaminacao") +
    xlab("")

print(grafico_checkm2_qc)

ggsave(
  file.path(DIR_SAIDA, "checkm2_completude_contaminacao.png"),
  grafico_checkm2_qc, width = 9, height = 5.5, dpi = 300
)
message("Grafico de completude x contaminacao salvo em: ", normalizePath(DIR_SAIDA))

# -----------------------------------------------------------------------
# 3) checkm2_quality - coding_density x average_gene_length
#    (escalas bem diferentes: um violino por variavel, sem misturar no
#     mesmo eixo y, para nao achatar a distribuicao)
# -----------------------------------------------------------------------

data <- data.frame(
  name  = "Coding density",
  value = as.numeric(checkm2_quality$coding_density)
)
data <- data[!is.na(data$value), ]
sample_size <- data %>% group_by(name) %>% summarize(num = n())

grafico_coding_density <- data %>%
  left_join(sample_size) %>%
  mutate(myaxis = paste0(name, "\n", "n=", num)) %>%
  ggplot(aes(x = myaxis, y = value, fill = name)) +
    geom_violin(width = 1.4) +
    geom_boxplot(width = 0.1, color = "grey", alpha = 0.2) +
    scale_fill_viridis(discrete = TRUE) +
    theme_ipsum(base_family = "sans") +
    theme(legend.position = "none", plot.title = element_text(size = 11)) +
    ggtitle("CheckM2: Coding density") +
    xlab("")

print(grafico_coding_density)

ggsave(
  file.path(DIR_SAIDA, "checkm2_coding_density.png"),
  grafico_coding_density, width = 9, height = 5.5, dpi = 300
)

data <- data.frame(
  name  = "Average gene length",
  value = as.numeric(checkm2_quality$average_gene_length)
)
data <- data[!is.na(data$value), ]
sample_size <- data %>% group_by(name) %>% summarize(num = n())

grafico_gene_length <- data %>%
  left_join(sample_size) %>%
  mutate(myaxis = paste0(name, "\n", "n=", num)) %>%
  ggplot(aes(x = myaxis, y = value, fill = name)) +
    geom_violin(width = 1.4) +
    geom_boxplot(width = 0.1, color = "grey", alpha = 0.2) +
    scale_fill_viridis(discrete = TRUE) +
    theme_ipsum(base_family = "sans") +
    theme(legend.position = "none", plot.title = element_text(size = 11)) +
    ggtitle("CheckM2: Average gene length") +
    xlab("")

print(grafico_gene_length)

ggsave(
  file.path(DIR_SAIDA, "checkm2_average_gene_length.png"),
  grafico_gene_length, width = 9, height = 5.5, dpi = 300
)
message("Graficos de coding_density e average_gene_length salvos em: ", normalizePath(DIR_SAIDA))
