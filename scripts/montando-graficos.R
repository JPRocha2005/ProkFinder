# Script R para gerar graficos e tabelas sugeridos em 'montando-graficos.txt'

# 0. Carregar bibliotecas

pacotes <- c("ggplot2", "dplyr", "readr", "scales", "janitor", "viridis", "hrbrthemes", "purrr", "patchwork", "gridExtra", "tidyr", "grid", "UpSetR")

# Identifica pacotes não instalados
ausentes <- pacotes[!(pacotes %in% installed.packages()[, "Package"])]

# Instala os pacotes ausentes, se houver
if (length(ausentes) > 0) {
  message("Instalando pacotes ausentes: ", paste(ausentes, collapse = ", "))
  install.packages(ausentes)
} else {
  message("Todos os pacotes já estão instalados.")
}

# Carrega todos os pacotes silenciosamente
invisible(lapply(pacotes, require, character.only = TRUE))

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


# ============= CRIAR TIBBLES =========================

# # 1) Recuperar genomas e os metadados
# orig_assembly <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ORIGINAL-METADATA/ASSEMBLY-METADATA.tsv"))
# orig_quality <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ORIGINAL-METADATA/QUALITY-METADATA.tsv"))
# orig_sample <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ORIGINAL-METADATA/SAMPLE-METADATA.tsv"))

# # 2) Filtragem dos genomas por dados de qualidade pelos metadados do QUALITY-METADATA.tsv 
# list_first_filter <- read_my_tsv(file.path(DIR_BASE, "lista-genomas-filtrados.txt"))
# therm_label_data <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/THERMOPHILIC-LABELED-METADATA.tsv"))

# # 3) Identificacao dos genomas de termofilos
# list_therm_only <- read_my_tsv(file.path(DIR_BASE, "lista-genomas-thermophilic.txt"))
# therm_only_data <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ONLY-THERMOPHILIC-METADATA.tsv"))

# # 4) Filtragem dos genomas com muitos gaps (bases N)
# list_few_gaps <- read_my_tsv(file.path(DIR_BASE, "lista-genomas-poucos-gaps.txt"))
# contig_gaps_table <- read_my_tsv(file.path(DIR_BASE, "SEQKIT-RESULTS/contagem-gaps-n-por-contig.txt"))

# # 5) Filtragem dos genomas pela completude e contaminacao calculados com CheckM2
# list_non_checkm2_filter <- read_my_tsv(file.path(DIR_BASE, "CHECKM2-RESULTS/lista_genomas.txt"))
# checkm2_quality <- read_my_tsv(file.path(DIR_BASE, "CHECKM2-RESULTS/quality_report.tsv"))

# list_checkm2_filter <- read_my_tsv(file.path(DIR_BASE, "lista-genomas-alta-qualidade.txt"))
   
# # 6) Busca pela classificacao taxonomica no GTDB
# gtdb_tax_table <- read_my_tsv(file.path(DIR_BASE, "TAXONOMY-DIRECTORY/TAXONOMY-TABLE.tsv"))
# list_non_classified_tax <- read_my_tsv(file.path(DIR_BASE, "TAXONOMY-DIRECTORY/lista-genomas-nao-classificados.txt"))
   
# # 7) Classificacao taxonomica dos genomas remanescentes
# ARC_TAX_FILE <- "gtdbtk.ar53.summary.tsv"
# BAC_TAX_FILE <- "gtdbtk.bac120.summary.tsv"
# archaea_tax <- ""
# bacteria_tax <- ""
# if (file.exists(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", ARC_TAX_FILE)) == TRUE) {
  # archaea_tax <- read_my_tsv(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", ARC_TAX_FILE))
# }
# if (file.exists(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", BAC_TAX_FILE)) != 0) {
  # bacteria_tax <- read_my_tsv(file.path(DIR_BASE, "GTDBTK-CLASSIFICATION/classify", BAC_TAX_FILE))
# }
# gtdb_gtdbtk_tax_table <- read_my_tsv(file.path(DIR_BASE, "TAXONOMY-DIRECTORY/COMPLETE-TAXONOMY-TABLE-2.tsv"))

# # 8) Desreplicacao dos genomas
# list_rep <- read_my_tsv(file.path(DIR_BASE, "lista-genomas-representativos.txt"))
# tabela_path_rep <- read_my_tsv(file.path(DIR_BASE, "tabela-dir-representativos.tsv"))

# current_assembly <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/ASSEMBLY-METADATA.tsv"))
# current_quality <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/QUALITY-METADATA.tsv"))
# current_sample <- read_my_tsv(file.path(DIR_BASE, "METADATA-DIRECTORY/SAMPLE-METADATA.tsv"))



# ================= TABELA DE CONTAGEM =========================

# # 1. Criando a tabela com o numero de genomas em cada etapa
# table_count_genomes <- tibble::tibble(
  # etapa = c(
    # "1. Total baixado do NCBI",
    # "2. Filtro de qualidade inicial",
    # "3. Identificacao como Termofilo",
    # "4. Filtro por n° de gaps (bases N)",
    # "5. Filtro por completude/contaminacao",
    # "6+7. Classificados taxonomicamente",
    # "8. Genomas representativos"
  # ), 
  # genomas = c(
    # nrow(orig_assembly)-1,
    # nrow(list_first_filter),
    # nrow(list_therm_only),
    # nrow(list_few_gaps),
    # nrow(list_checkm2_filter),
    # nrow(gtdb_gtdbtk_tax_table)-1,
    # nrow(list_rep)
  # )
# )

# # 2. Incluindo porcentagens na tabela
# table_count_genomes <- table_count_genomes |> mutate(
    # pct_do_total = genomas / first(genomas) * 100,
    # pct_da_anterior = genomas / lag(genomas, default = first(genomas)) * 100,
    # etapa = factor(etapa, levels = rev(etapa))  # preserva ordem no grafico
# )
# print(table_count_genomes)
 

# # 3. Formatando tabela 
# tabela_formatada <- table_count_genomes %>%
  # mutate(
    # Etapa          = as.character(etapa),
    # `Genomas restantes` = trimws(format(genomas, big.mark = ".", decimal.mark = ",", scientific = FALSE)),
    # `% do total`   = paste0(trimws(format(round(pct_do_total, 1), decimal.mark = ",")), "%"),
    # `% da etapa anterior` = paste0(trimws(format(round(pct_da_anterior, 1), decimal.mark = ",")), "%")
  # ) %>%
# select(Etapa, `Genomas restantes`, `% do total`, `% da etapa anterior`) %>%
# arrange(match(Etapa, rev(levels(table_count_genomes$etapa))))

# print(tabela_formatada)
  
# # 4. Salvar tabela em TSV (para abrir em Excel/planilhas)
# write.table(
  # tabela_formatada,
  # file.path(DIR_SAIDA, "funil_filtragem.tsv"),
  # sep = "\t", row.names = FALSE, quote = FALSE, fileEncoding = "UTF-8"
# )

# # 4.1 Salvar tabela em Markdown (para colar em relatorios/README)
# linhas_md <- c(
  # paste0("| ", paste(names(tabela_formatada), collapse = " | "), " |"),
  # paste0("|", paste(rep("---", ncol(tabela_formatada)), collapse = "|"), "|"),
  # apply(tabela_formatada, 1, function(x) paste0("| ", paste(x, collapse = " | "), " |"))
# )
# writeLines(linhas_md, file.path(DIR_SAIDA, "funil_filtragem.md"))

# # 5. Gerando grafico de funil
# grafico_barra_contagem <- ggplot(table_count_genomes, aes(x = etapa, y = genomas)) +
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
  # grafico_barra_contagem, width = 9, height = 5.5, dpi = 300
# )

# message("Tabela e grafico salvos em: ", normalizePath(DIR_SAIDA))

# ================= ANALISE DA QUALIDADE DOS GENOMAS =========================

# 3 ANALISES:

# -----------------------------------------------------------------------
# 1) orig_quality x current_quality - um violino por coluna numerica
# -----------------------------------------------------------------------

# COLUNAS:
# orig_quality e current_quality
  # [2] "assembly_stats_atgc_count"
  # [3] "assembly_stats_contig_l50"
  # [4] "assembly_stats_contig_n50"
  # [6] "assembly_stats_gc_percent"
  # [7] "assembly_stats_genome_coverage"
  # [9] "assembly_stats_number_of_contigs"
  
# cols_quality <- c(
  # "assembly_stats_atgc_count",
  # "assembly_stats_contig_l50",
  # "assembly_stats_contig_n50",
  # "assembly_stats_gc_percent",
  # "assembly_stats_genome_coverage",
  # "assembly_stats_number_of_contigs"
# )
  
# y_labels <- c(
  # assembly_stats_atgc_count        = "ATGC count (bp)",
  # assembly_stats_contig_l50        = "Contig L50",
  # assembly_stats_contig_n50        = "Contig N50 (bp)",
  # assembly_stats_gc_percent        = "GC content (%)",
  # assembly_stats_genome_coverage   = "Genome coverage (x)",
  # assembly_stats_number_of_contigs = "Number of contigs"
# )
# x_labels <- c(
  # assembly_stats_atgc_count        = "ATGC count (bp)",
  # assembly_stats_contig_l50        = "Contig L50",
  # assembly_stats_contig_n50        = "Contig N50 (bp)",
  # assembly_stats_gc_percent        = "GC content (%)",
  # assembly_stats_genome_coverage   = "Genome coverage (x)",
  # assembly_stats_number_of_contigs = "Number of contigs"
# )

# # Junta os dois tibbles em um único data frame, marcando a origem
# combined <- bind_rows(
  # orig_quality    %>% mutate(dataset = "orig_quality"),
  # current_quality %>% mutate(dataset = "current_quality")
# )

# # Função auxiliar: conta outliers pela regra do IQR (1.5x)
# count_outliers <- function(x) {
  # x <- x[!is.na(x)]
  # if (length(x) < 4) return(0L)
  # q1  <- quantile(x, 0.25, na.rm = TRUE)
  # q3  <- quantile(x, 0.75, na.rm = TRUE)
  # iqr <- q3 - q1
  # lower <- q1 - 1.5 * iqr
  # upper <- q3 + 1.5 * iqr
  # sum(x < lower | x > upper)
# }

# =================== VIOLINO =======================  
# make_violin <- function(col) {

  # df <- combined %>%
    # select(dataset, value = all_of(col)) %>%
    # filter(!is.na(value))

  # # decide automaticamente se usa escala log:
  # # baseado na razao entre o maior e o menor valor positivo
  # pos <- df$value[df$value > 0]
  # use_log <- length(pos) > 0 && (max(pos) / min(pos) > 1000)

  # # estatisticas por grupo: n, media (m) e n de outliers (o)
  # stats <- df %>%
    # group_by(dataset) %>%
    # summarise(
      # n = n(),
      # m = mean(value, na.rm = TRUE),
      # o = count_outliers(value),
      # .groups = "drop"
    # ) %>%
    # mutate(
      # label = sprintf(
        # "%s\nn=%s | m=%s | o=%s",
        # dataset,
        # format(n, big.mark = ".", scientific = FALSE),
        # format(round(m, 2), big.mark = ".", scientific = FALSE),
        # o
      # )
    # )

  # df <- df %>% left_join(stats, by = "dataset")

  # p <- ggplot(df, aes(x = label, y = value, fill = dataset)) +
    # # width baixo pra nao "engordar" o violino com muitos dados (ate 30k pontos)
    # geom_violin(width = 0.6, scale = "width", trim = TRUE) +
    # geom_boxplot(width = 0.08, color = "grey30", alpha = 0.3,
                 # outlier.size = 0.4, outlier.alpha = 0.3) +
    # scale_fill_viridis_d(option = "D") +
    # theme_minimal(base_size = 12) +
    # theme(
      # legend.position = "none",
      # plot.title = element_text(size = 12, face = "bold"),
      # axis.text.x = element_text(lineheight = 1.1)
    # ) +
    # xlab("") +
    # ylab(y_labels[[col]]) +
    # ggtitle(y_labels[[col]])

  # if (use_log) {
    # p <- p + scale_y_log10(labels = label_number(big.mark = "."))
  # }

  # p
# }

# # Gera todos os graficos e salva em PDF
# plots <- map(cols_quality, make_violin)
# names(plots) <- cols_quality

# pdf("violin_quality_comparison.pdf", width = 7, height = 5)
# walk(plots, print)
# dev.off()

# grid_plot <- wrap_plots(plots, ncol = 2)
# ggsave("violin_quality_comparison_grid.pdf", grid_plot, width = 14, height = 15)
  
# ====================== BOXPLOT ===============================

# make_boxplot <- function(col) {

  # df <- combined %>%
    # select(dataset, value = all_of(col)) %>%
    # filter(!is.na(value))

  # # decide automaticamente se usa escala log:
  # # baseado na razao entre o maior e o menor valor positivo
  # pos <- df$value[df$value > 0]
  # use_log <- length(pos) > 0 && (max(pos) / min(pos) > 1000)

  # # estatisticas por grupo: n, media (m) e desvio padrao (s)
  # stats <- df %>%
    # group_by(dataset) %>%
    # summarise(
      # n = n(),
      # m = mean(value, na.rm = TRUE),
      # s = sd(value, na.rm = TRUE),
      # .groups = "drop"
    # ) %>%
    # mutate(
      # label = sprintf(
        # "%s\nn=%s | m=%s | s=%s",
        # dataset,
        # format(n, big.mark = ".", scientific = FALSE),
        # format(round(m, 2), big.mark = ".", scientific = FALSE),
        # format(round(s, 2), big.mark = ".", scientific = FALSE)
      # )
    # )

  # df <- df %>% left_join(stats, by = "dataset")

  # p <- ggplot(df, aes(x = label, y = value, fill = dataset)) +
    # geom_boxplot(alpha = 0.4, outlier.size = 0.5, outlier.alpha = 0.4) +
    # scale_fill_viridis_d(option = "D") +
    # theme_minimal(base_size = 12) +
    # theme(
      # legend.position = "none",
      # plot.title = element_text(size = 12, face = "bold"),
      # axis.text.x = element_text(lineheight = 1.1)
    # ) +
    # xlab("") +
    # ylab(y_labels[[col]]) +
    # ggtitle(y_labels[[col]])

  # if (use_log) {
    # p <- p + scale_y_log10(labels = label_number(big.mark = "."))
  # }

  # p
# }

# # Gera todos os graficos
# plots <- map(cols_quality, make_boxplot)
# names(plots) <- cols_quality

# # PDF com um grafico por pagina (nao precisa de pacote extra)
# pdf("boxplot_quality_comparison.pdf", width = 7, height = 5)
# walk(plots, print)
# dev.off()

# # PDF com todos os graficos juntos em uma grade (2 colunas)
# # precisa do pacote patchwork -> install.packages("patchwork")
# library(patchwork)
# grid_plot <- wrap_plots(plots, ncol = 2)
# ggsave("boxplot_quality_comparison_grid.pdf", grid_plot, width = 14, height = 15)  
  
  
  
# ====================== HISTOGRAMA ===============================

# make_histogram <- function(col) {
 
  # df <- combined %>%
    # select(dataset, value = all_of(col)) %>%
    # filter(!is.na(value))
 
  # # decide automaticamente se usa escala log no eixo X:
  # # baseado na razao entre o maior e o menor valor positivo
  # pos <- df$value[df$value > 0]
  # use_log <- length(pos) > 0 && (max(pos) / min(pos) > 1000)
 
  # # usa DENSIDADE em vez de contagem: como orig_quality e current_quality
  # # tem numero de linhas bem diferente, comparar contagem bruta nao e justo.
  # # a densidade normaliza cada histograma para area = 1, comparando so o
  # # formato/moda da distribuicao.
  # p <- ggplot(df, aes(x = value, fill = dataset)) +
    # geom_histogram(
      # aes(y = after_stat(density)),
      # color = "#e9ecef", alpha = 0.6, position = "identity", bins = 40
    # ) +
    # scale_fill_manual(
      # values = c(orig_quality = "#69b3a2", current_quality = "#404080")
    # ) +
    # theme_minimal(base_size = 12) +
    # theme(
      # legend.position = "top",
      # plot.title = element_text(size = 12, face = "bold")
    # ) +
    # labs(fill = "") +
    # xlab(x_labels[[col]]) +
    # ylab("Densidade") +
    # ggtitle(x_labels[[col]])
 
  # if (use_log) {
    # p <- p + scale_x_log10(labels = label_number(big.mark = "."))
  # }
 
  # p
# }
 
# # Gera todos os graficos
# plots <- map(cols_quality, make_histogram)
# names(plots) <- cols_quality
 
# # Opcao A: PDF com um grafico por pagina (nao precisa de pacote extra)
# pdf("histogram_quality_comparison.pdf", width = 7, height = 5)
# walk(plots, print)
# dev.off()
 
# # Opcao B: PDF com todos os graficos juntos em uma grade (2 colunas)
# # precisa do pacote patchwork -> install.packages("patchwork")
# library(patchwork)
# grid_plot <- wrap_plots(plots, ncol = 2)
# ggsave("histogram_quality_comparison_grid.pdf", grid_plot, width = 14, height = 15)



# ====================== DENSIDADE ESPELHADA ===============================

# # Função auxiliar: acha o pico (x, y) da densidade de um vetor
# find_peak <- function(x) {
  # d <- density(x, na.rm = TRUE)
  # data.frame(x = d$x[which.max(d$y)], y = max(d$y))
# }

# # Função principal: monta a densidade espelhada de uma coluna
# make_mirrored_density <- function(col) {

  # v1 <- orig_quality[[col]]
  # v2 <- current_quality[[col]]
  # v1 <- v1[!is.na(v1)]
  # v2 <- v2[!is.na(v2)]

  # # decide automaticamente se usa escala log no eixo X:
  # # baseado na razao entre o maior e o menor valor positivo (dos 2 grupos)
  # all_vals <- c(v1, v2)
  # pos <- all_vals[all_vals > 0]
  # use_log <- length(pos) > 0 && (max(pos) / min(pos) > 1000)

  # # posicao dos rotulos: no pico de cada densidade
  # peak1 <- find_peak(v1)
  # peak2 <- find_peak(v2)

  # p <- ggplot() +
    # # Metade de cima: orig_quality
    # geom_density(aes(x = v1, y = after_stat(density)),
                 # fill = "#69b3a2", color = "#69b3a2", alpha = 0.8) +
    # geom_label(aes(x = peak1$x, y = peak1$y * 1.15, label = "orig_quality"),
               # color = "#69b3a2") +
    # # Metade de baixo: current_quality (densidade invertida)
    # geom_density(aes(x = v2, y = -after_stat(density)),
                 # fill = "#404080", color = "#404080", alpha = 0.8) +
    # geom_label(aes(x = peak2$x, y = -peak2$y * 1.15, label = "current_quality"),
               # color = "#404080") +
    # theme_minimal(base_size = 12) +
    # theme(plot.title = element_text(size = 12, face = "bold")) +
    # xlab(x_labels[[col]]) +
    # ylab("Densidade") +
    # ggtitle(x_labels[[col]])

  # if (use_log) {
    # p <- p + scale_x_log10(labels = label_number(big.mark = ".", decimal.mark = ","))
  # }

  # p
# }

# # Gera todos os graficos
# plots <- map(cols_quality, make_mirrored_density)
# names(plots) <- cols_quality

# # Opcao A: PDF com um grafico por pagina (nao precisa de pacote extra)
# pdf("mirrored_density_quality_comparison.pdf", width = 7, height = 5)
# walk(plots, print)
# dev.off()

# # Opcao B: PDF com todos os graficos juntos em uma grade (2 colunas)
# # precisa do pacote patchwork -> install.packages("patchwork")
# library(patchwork)
# grid_plot <- wrap_plots(plots, ncol = 2)
# ggsave("mirrored_density_quality_comparison_grid.pdf", grid_plot, width = 14, height = 15)

  
# -----------------------------------------------------------------------
# 2) checkm2_quality - completude x contaminacao, lado a lado
# -----------------------------------------------------------------------

# COLUNAS:
# # checkm2_quality
  # [2] "completeness"
  # [3] "contamination"   

cols_checkm2 <- c(
  "completeness",
  "contamination" 
)  

# -----------------------------------------------------------------------
# 3) checkm2_quality - coding_density x average_gene_length
#    (escalas bem diferentes: um violino por variavel, sem misturar no
#     mesmo eixo y, para nao achatar a distribuicao)
# -----------------------------------------------------------------------

# COLUNAS:
# checkm2_quality
  # [6] "coding_density"
  # [8] "average_gene_length"
  # [11] "total_coding_sequences"  
cols_genes_checkm2 <- c(
  "coding_density",
  "average_gene_length",
  "total_coding_sequences"  
)

# ======================= ANALISE DOS DADOS DE TAXONOMIA ==============================

# # Tibble: gtdb_gtdbtk_tax_table

# # Definindo lista de ranks taxonômicos para reutilização
# ranks <- c("domain", "phylum", "class", "order", "family", "genus", "species")

# # ==============================================================================
# # 1. Tabela com a contagem do número de valores diferentes em todas as colunas
# # ==============================================================================

# tabela_unicos <- gtdb_gtdbtk_tax_table %>%
  # summarise(across(everything(), ~ n_distinct(.))) %>%
  # pivot_longer(
    # cols = everything(),
    # names_to = "coluna",
    # values_to = "valores_unicos"
  # )

# # ==============================================================================
# # 2. Gráfico de barras comparando os valores da col classification_by
# # ==============================================================================

# df_classification <- gtdb_gtdbtk_tax_table %>%
  # count(classification_by, name = "genomas") %>%
  # mutate(pct_do_total = (genomas / sum(genomas)) * 100)

# grafico_classification <- ggplot(df_classification, aes(x = classification_by, y = genomas)) +
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
    # title = "Distribuição por Método de Classificação",
    # x = NULL,
    # y = "Número de genomas"
  # ) +
  # theme_minimal(base_size = 12) +
  # theme(
    # plot.title = element_text(face = "bold"),
    # panel.grid.major.y = element_blank(),
    # panel.grid.minor = element_blank()
  # )

# # ==============================================================================
# # 3. Gráfico de barras verticais com o número de valores únicos em cada rank
# # ==============================================================================

# df_ranks_unicos <- gtdb_gtdbtk_tax_table %>%
  # summarise(across(all_of(ranks), ~ n_distinct(.))) %>%
  # pivot_longer(
    # cols = everything(),
    # names_to = "rank",
    # values_to = "valores_unicos"
  # ) %>%
  # mutate(
    # rank = factor(rank, levels = ranks),
    # pct_do_total = (valores_unicos / sum(valores_unicos)) * 100
  # )

# grafico_ranks_unicos <- ggplot(df_ranks_unicos, aes(x = rank, y = valores_unicos)) +
  # geom_col(fill = "#2C7FB8", width = 0.7) +
  # geom_text(
    # aes(label = format(valores_unicos, big.mark = ".", decimal.mark = ",")),
    # vjust = -0.5, size = 3.4
  # ) +
  # scale_y_continuous(
    # labels = label_number(big.mark = ".", decimal.mark = ","),
    # expand = expansion(mult = c(0, 0.15))
  # ) +
  # labs(
    # title = "Número de Táxons Únicos por Rank Taxonômico",
    # x = "Rank Taxonômico",
    # y = "Número de táxons únicos"
  # ) +
  # theme_minimal(base_size = 12) +
  # theme(
    # plot.title = element_text(face = "bold"),
    # panel.grid.major.x = element_blank(),
    # panel.grid.minor = element_blank()
  # )

# # ==============================================================================
# # 4 & 5. Top 5 táxons mais representados para cada rank e exportação conjunta
# # ==============================================================================

# total_genomas <- nrow(gtdb_gtdbtk_tax_table)

# plots_top5 <- map(ranks, function(rk) {
  # df_top5 <- gtdb_gtdbtk_tax_table %>%
    # count(taxon = .data[[rk]], name = "genomas") %>%
    # filter(!is.na(taxon) & taxon != "") %>%
    # slice_max(order_by = genomas, n = 5, with_ties = FALSE) %>%
    # mutate(
      # pct_do_total = (genomas / total_genomas) * 100,
      # taxon = reorder(taxon, genomas)
    # )

  # ggplot(df_top5, aes(x = taxon, y = genomas)) +
    # geom_col(fill = "#2C7FB8", width = 0.7) +
    # geom_text(
      # aes(label = paste0(format(genomas, big.mark = ".", decimal.mark = ","), "  (", round(pct_do_total, 1), "%)")),
      # hjust = -0.05, size = 3.2
    # ) +
    # coord_flip(clip = "off") +
    # scale_y_continuous(
      # labels = label_number(big.mark = ".", decimal.mark = ","),
      # expand = expansion(mult = c(0, 0.30))
    # ) +
    # labs(
      # title = paste0("Top 5 Táxons - ", paste0(toupper(substr(rk, 1, 1)), substr(rk, 2, nchar(rk)))),
      # x = NULL,
      # y = "Número de genomas"
    # ) +
    # theme_minimal(base_size = 11) +
    # theme(
      # plot.title = element_text(face = "bold"),
      # panel.grid.major.y = element_blank(),
      # panel.grid.minor = element_blank()
    # )
# })

# # Salvar em pdf
# pdf("relatorio_taxonomia_completo.pdf", width = 7, height = 5)
# # Página 1: Tabela de contagem de únicos
# grid.draw(tableGrob(tabela_unicos))
# # Página 2: Barra da coluna classification_by
# print(grafico_classification)
# # Página 3: Barra vertical com número de valores únicos por rank
# print(grafico_ranks_unicos)

# # Salvar em pdf unifo
# pdf("top5_taxons_juntos.pdf", width = 12, height = 10)
# # Junta todos os gráficos da lista em 2 colunas
# print(wrap_plots(plots_top5, ncol = 2))

# dev.off()


# =================== UPSET PARA ORIGEM DA IDENTIFICACAO ================================
# > colnames(therm_label_data)
 # [6] "classification_isolation_source"
 # [8] "classification_literature"
 # [9] "classification_bacdive"
# [10] "classification_tempura"
# [11] "classification_thermobase"
# [12] "classification_general"

origem_identificao <- c("Isolation source", "Literature", "BacDive", "Tempura", "Thermobase")

# 1. Preparação considerando QUALQUER valor presente (não NA) como TRUE (1)
df_upset <- therm_label_data %>%
  select(
    `Isolation source` = classification_isolation_source,
    `Literature`       = classification_literature,
    `BacDive`          = classification_bacdive,
    `Tempura`          = classification_tempura,
    `Thermobase`       = classification_thermobase
  ) %>%
  # Qualquer valor que não seja NA vira 1, NAs viram 0
  mutate(across(everything(), ~ if_else(!is.na(.) & . != "", 1, 0))) %>%
  filter(rowSums(across(everything())) > 0) %>%
  as.data.frame()

# Checagem rápida no terminal para confirmar se há dados
print(paste("Linhas restantes para o UpSet:", nrow(df_upset)))

# 2. Gerar e salvar o PDF
pdf("upset_origem_identificacao.pdf", width = 9, height = 6)

upset(
  df_upset,
  sets = origem_identificao,
  keep.order = TRUE,
  nintersects = 40,
  order.by = "freq",
  decreasing = TRUE,
  mb.ratio = c(0.6, 0.4),
  number.angles = 0,
  text.scale = 1.1,
  point.size = 2.8,
  line.size = 1,
  sets.bar.color = "#2C7FB8",
  main.bar.color = "#2C7FB8"
)

dev.off()

# =================== RANKING COM BOXPLOTS ================================

# 1. Contar a frequencia para cada rank taxonomico
# 2. Montar graficos de barra horizontal com os 5 valores mais frequentes para cada rank
# (dominio, filo, classe, ..., especie)
# Seguir a referencia:
# grafico_barra_contagem <- ggplot(table_count_genomes, aes(x = etapa, y = genomas)) +
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


# RANKING DAS 5 FONTES DE ISOLAMENTO MAIS COMUNS
# > colnames(therm_label_data)
 # [7] "isolation_source_thermophilic_keyword"

# RANKING DAS 



