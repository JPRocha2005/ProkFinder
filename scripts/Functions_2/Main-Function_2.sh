# Funcoes para criação do banco de dados curado

# --- FUNÇÕES DE CONTROLE DE ETAPAS ---

executar_etapa () {
    local num_etapa="$1"
    # Só executa se a ETAPA_ATUAL for menor ou igual à etapa que chamou a função
    # Isso garante que a execucao continue a partir da etapa que parou (1, 2, 3, 4, ...)
    if [ "$ETAPA_ATUAL" -le "$num_etapa" ]; then
        ETAPA_ATUAL=$num_etapa
        mensagem_etapa "${ETAPA_ATUAL}"
        return 0 # Pode executar
    fi
    return 1 # Pula a etapa (já foi feita antes)
}

checar_argumentos () {
    local FILES=()
    local DIRS=()

    # Loop para ler as flags e os respectivos args
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -f | --file)
                shift # Consome a flag '-f'
                # Loop para ler tudo o que vem depois até achar outra flag
                while [[ "$#" -gt 0 && ! "$1" =~ ^- ]]; do
                    if [ -f "$1" ]; then
                        FILES+=("$1")
                    else
                        echo_erro "Arquivo '$1' nao encontrado em $(pwd)"
                        return 1
                    fi
                    shift # Consome o argumento
                done
                ;;
            -d | --directory)
                shift # Consome a flag '-d'
                # Loop para ler tudo o que vem depois até achar outra flag
                while [[ "$#" -gt 0 && ! "$1" =~ ^- ]]; do
                    if [ -d "$1" ]; then
                        DIRS+=("$1")
                    else
                        echo_erro "Diretorio '$1' nao encontrado em $(pwd)"
                        return 1
                    fi
                    shift # Consome o argumento
                done
                ;;
            *)
                echo "[ERRO INTERNO] Argumento '$1' invalido. Uso: $FUNCNAME -f <lista_arquivos> -d <lista_diretorios>"
                return 1
                ;;
        esac 
    done
}

encontrar_caminho_genoma () {
    local PASTA_GENOMAS="${A_DIR_GENOMAS}/ncbi_dataset/data/"
    local EXTENSAO_GENOMA="$F_EXTENSAO_ARQUIVO_GENOMA"
    local OUTPUT_CAMINHOS_GENOMAS="${1?}"
    local LISTA_GENOMAS="$2" # opcional, mas caso informado deve existir e nao estar vazio

    # Zero/empty check (-z)
    [ -z "$A_DIR_GENOMAS" ] && { echo "[ERRO] Variavel A_DIR_GENOMAS vazia!" >> "$LOG_FILE" ; return 1 ; }
    [ -z "$F_EXTENSAO_ARQUIVO_GENOMA" ] && { echo "[ERRO] Variavel F_EXTENSAO_ARQUIVO_GENOMA vazia!" >> "$LOG_FILE" ; return 1 ; }

    # Non-zero size check (-n)
    if [ -n "$LISTA_GENOMAS" ]; then
        # Size check (-s)
        [ -s "$LISTA_GENOMAS" ] || { echo "[ERRO] LISTA_GENOMAS $LISTA_GENOMAS nao foi encontrada ou esta vazia!" >> "$LOG_FILE" ; return 1 ; }
    fi

    # Directory check (-d)
    [ -d "$PASTA_GENOMAS" ] || { echo "[ERRO] Diretorio $PASTA_GENOMAS nao encontrado!" >> "$LOG_FILE" ; return 1 ; }

    # Execução com ou sem filtro da lista de genomas
    if [ -n "$LISTA_GENOMAS" ]; then
        find "$PASTA_GENOMAS" -maxdepth 1 -name "*.$EXTENSAO_GENOMA" | grep -Ff "$LISTA_GENOMAS" > "$OUTPUT_CAMINHOS_GENOMAS"
    else
        find "$PASTA_GENOMAS" -maxdepth 1 -name "*.$EXTENSAO_GENOMA" > "$OUTPUT_CAMINHOS_GENOMAS"
    fi

    # Verificacao dos status do comando find/grep
    if [ $? -ne 0 ]; then
        echo "[ERRO] Falha ao listar/filtrar genomas na funcao ${FUNCNAME[0]}" >> "$LOG_FILE"
        return 1
    fi
}

encontrar_id_genoma () {
    local OUTPUT_ID_GENOMAS="${1?}"
    local LISTA_GENOMAS="$2"
    local CAMINHOS_GENOMAS=$(mktemp)
    
    # Buscar pelos caminhos dos genomas
    encontrar_caminho_genoma "$CAMINHOS_GENOMAS" "$LISTA_GENOMAS"
    
    # Converter para o ID, caso o output dos caminhos exista
    if [ -s "$CAMINHOS_GENOMAS" ]; then
        awk -F'\t' '
        {
            caminho_genoma = $0
            id_genoma = ""
            
            # Encontrar o id do genoma
            if (match(caminho_genoma, /GC[AF]_[0-9]+\.[0-9]+/)) {
                id_genoma = substr($0, RSTART, RLENGTH)
            }
            
            # Imprimir o id
            print id_genoma
            
        } ' "$CAMINHOS_GENOMAS" > "$OUTPUT_ID_GENOMAS" \
            || { echo "[ERRO] Comando awk falhou na funcao ${FUNCNAME[0]}" >> "$LOG_FILE" ; return 1 ; }
    else
        echo "[ERRO] Nenhum caminho de genoma encontrado na funcao ${FUNCNAME[0]}" >> "$LOG_FILE"
        return 1
    fi
}

limpar_diretorio () {
    local DIR_PARA_LIMPAR="${1?}"
    
    # Caso o diretorio exista, apague-o
    if [ -d "$DIR_PARA_LIMPAR" ]; then 
        rm -rf "$DIR_PARA_LIMPAR" 
    fi
    
    # Criando diretorio limpo
    mkdir -p "$DIR_PARA_LIMPAR" \
        || { echo "[ERRO] Nao foi possivel gerar diretorio $DIR_PARA_LIMPAR!" >> "$LOG_FILE" ; return 1 ; }
}

avancar_pipeline () {
    (( ETAPA_ATUAL+=1 ))
    save_step "${ETAPA_ATUAL}"
}

# --- DEFINIÇÃO DAS ETAPAS DA PIPELINE ---

# 1) Download de genomas desidratados do NCBI
etapa_1() {   
    # 1 - CARREGAR VARIAVEIS GLOBAIS
    A_BANCO_GENOMAS="GenBank" # GenBank ou RefSeq (default - GenBank)
    A_DIR_GENOMAS="GENOMES-DIRECTORY" # Nomes de diretorios (comecam com NUM_)
    
    # 2 - CHECAR SE A ETAPA JA FOI EXECUTADA
    executar_etapa 1 || return 0
    
    # 3 - VERIFICAR ARGUMENTOS DA FUNCAO
    # checar_argumentos (nao necessario)
    
    # 4 - CHAMAR FUNCAO DA ETAPA
    # Uso: download_genomes_by_taxid <numero_taxid> <banco_dados> <output_dir_genomas>
    download_genomes_by_taxid "$TAXID_ANALISADO" "$A_BANCO_GENOMAS" "$A_DIR_GENOMAS" \
        || { echo_erro "Funcao download_genomes_by_taxid falhou!"; return 1 ; }
        
    # 5 - SALVAR A ETAPA CONCLUIDA
    avancar_pipeline
}

# 2) Gerar tabelas de metadados formatados em TSV
etapa_2() {
    B_METADADOS_GENOMAS_JSON="${A_DIR_GENOMAS}/ncbi_dataset/data/assembly_data_report.jsonl"
    B_DIR_METADADOS_TSV="METADATA-DIRECTORY"
    [ "$A_BANCO_GENOMAS" == "GenBank" ] && B_PREFIXO_NOME_GENOMA="GCA_"
    [ "$A_BANCO_GENOMAS" == "RefSeq" ] && B_PREFIXO_NOME_GENOMA="GCF_" 
    
    executar_etapa 2 || return 0
    checar_argumentos -d "$A_DIR_GENOMAS" -f "$B_METADADOS_GENOMAS_JSON" || return 1
    
    # Uso: gerar_tabelas_metadados_tsv <metadados_json> <dir_output_metadados> <prefixo_genoma>
    gerar_tabelas_metadados_tsv "$B_METADADOS_GENOMAS_JSON" "$B_DIR_METADADOS_TSV" "$B_PREFIXO_NOME_GENOMA" \
        || { echo_erro "Funcao gerar_tabelas_metadados_tsv falhou!"; return 1 ; }
    
    avancar_pipeline
}


# Como organizar as 4 tabelas diferentes de metadados
# Eu preciso ir atualizando as tabelas a medida que eu for fazendo as filtragens
# Como organizar isso?

# 3) Filtragem dos genomas pelos metadados de qualidade dos genomas
etapa_3() { 
    C_METADADOS_QUALIDADE="${B_DIR_METADADOS_TSV}/QUALITY-METADATA.tsv"
    C_NUMERO_CONTIGS_MAX="1000"
    C_COBERTURA_MIN="50"
    C_N50_BP_MIN="5000"
    C_LISTA_GENOMAS_FILTRADOS="lista-genomas-filtrados.txt"
    C_DIR_METADADOS_INDESEJADOS="${B_DIR_METADADOS_TSV}/REMOVED-METADATA"
    C_DIR_METADADOS_ORIGINAIS="${B_DIR_METADADOS_TSV}/ORIGINAL-METADATA"
    
    executar_etapa 3 || return 0
    checar_argumentos -d "$B_DIR_METADADOS_TSV" -f "$C_METADADOS_QUALIDADE" || return 1
    
    # Uso: filtrar_genomas_pela_qualidade <tabela_qualidade_genomas> <max_contigs> <min_cobertura> <min_n50>
    filtrar_genomas_pela_qualidade "$C_METADADOS_QUALIDADE" "$C_NUMERO_CONTIGS_MAX" "$C_COBERTURA_MIN" "$C_N50_BP_MIN" "$C_LISTA_GENOMAS_FILTRADOS" \
        || { echo_erro "Funcao filtrar_genomas_pela_qualidade falhou!" ; return 1 ; }
        
    checar_argumentos -f "$C_LISTA_GENOMAS_FILTRADOS" || return 1
    
    # Uso: atualizar_tabelas_metadados <lista_genomas:coluna unica:sem HEADER:caminho/acesso do genoma> <dir_metadados_selecionados> <dir_metadados_removidos> <dir_metadados_originais:OPCIONAL>
    atualizar_tabelas_metadados "$C_LISTA_GENOMAS_FILTRADOS" "$B_DIR_METADADOS_TSV" "$C_DIR_METADADOS_INDESEJADOS" "$C_DIR_METADADOS_ORIGINAIS" \
        || { echo_erro "Funcao atualizar_tabelas_metadados falhou!" ; return 1 ; }
        
    avancar_pipeline
}

# 4) Identificacao de grupo extremofilico (como termofilo, alcalofilo,  ex.)
etapa_4() {
    # LER DIRETO DA LINHA DE EXECUCAO
    D_CATEGORIA="THERMOPHILIC" # identificacao / categorizacao / label nos genomas
    
    # DEPOIS EU PRECISO DEIXAR ESSAS TABELAS DE UMA MANEIRA QUE POSSAM SER LIDAR DIRETO DA LINHA DE EXECUCAO E NAO ALTERADAS NO PROGRAMA
    D_DIR_DADOS="$(realpath ../../data)"
    D_ARQUIVO_FONTES_ISOLAMENTO="isolation-source.txt" # precisam conter o taxid e ser tsv
    D_VETOR_TABELAS_TAXID=( "pubmed-literature.tsv"  "MODIFIED-bacdive-thermophile-strains.tsv" "MODIFIED-tempura.tsv" "MODIFIED-thermobase.tsv" )
    D_VETOR_NOME_TAXID=( "LITERATURE" "BACDIVE" "TEMPURA" "THERMOBASE")
    D_VETOR_COLUNA_TAXID=( 2 3 3 3 )
    
    # VARIAVEIS QUE DEVEM SER MANTIDAS AQUI NA FUNCAO
    D_METADADOS_GERAIS="${B_DIR_METADADOS_TSV}/GENERAL-METADATA.tsv"
    D_METADADOS_CLASSIFICADOS="${B_DIR_METADADOS_TSV}/${D_CATEGORIA}-LABELED-METADATA.tsv"
    D_METADADOS_APENAS_CATEGORIA="${B_DIR_METADADOS_TSV}/ONLY-${D_CATEGORIA}-METADATA.tsv" 
    D_LISTA_GENOMAS_CATEGORIA="lista-genomas-${D_CATEGORIA,,}.txt" # o ',,' deixa o conteudo da variavel em lower case
    
    executar_etapa 4 || return 0
    checar_argumentos  -d "$D_DIR_DADOS" "$B_DIR_METADADOS_TSV"  -f "$D_METADADOS_GERAIS" || return 1
    
    # Uso: add_category_metadata <input_nao_categorizado> <diretorio_dados_referencia> <vetor_tabelas_dados> <vetor_nome_tabelas> <vetor_coluna_taxid> <fontes_isolamento> <categoria> <valor_nulo> <output_categorizado> <output_apenas_categorizados>
    add_category_metadata "$D_METADADOS_GERAIS" "$D_DIR_DADOS" \
        D_VETOR_TABELAS_TAXID D_VETOR_NOME_TAXID D_VETOR_COLUNA_TAXID \
        "$D_ARQUIVO_FONTES_ISOLAMENTO" "$D_CATEGORIA" \
        "$D_METADADOS_CLASSIFICADOS" "$D_METADADOS_APENAS_CATEGORIA" "$D_LISTA_GENOMAS_CATEGORIA" \
        || { echo_erro "Funcao add_category_metadata falhou!"; return 1 ; }
        
    avancar_pipeline
}

# 5) Selecao e reidratacao dos genomas da categoria escolhida
etapa_5() {
    E_ARQUIVO_URL_GENOMAS="${A_DIR_GENOMAS}/ncbi_dataset/fetch.txt"
    E_ARQUIVO_URL_GENOMAS_CATEGORIA="${A_DIR_GENOMAS}/ncbi_dataset/fetch-${D_CATEGORIA}.txt"
    E_NUMERO_CONEXOES=10 # numero de requisicoes simultaneas para server do NCBI
    E_DOWNLOAD_GZIP="true"
    E_PASTA_FASTA_GENOMAS="${A_DIR_GENOMAS}/ncbi_dataset/data"
    
    executar_etapa 5 || return 0
    checar_argumentos -f "$E_ARQUIVO_URL_GENOMAS" "$D_METADADOS_APENAS_CATEGORIA" || return 1
    
    # Uso: update_genomes_url_file <fetch.txt original> <metadados_categoria> <fetch.txt atualizado> <categoria>
    update_genomes_url_file "$E_ARQUIVO_URL_GENOMAS" "$D_METADADOS_APENAS_CATEGORIA" "$E_ARQUIVO_URL_GENOMAS_CATEGORIA" "$D_CATEGORIA" \
        || { echo_erro "Funcao update_genomes_url_file falhou!"; return 1 ; }
    
    checar_argumentos -d "$A_DIR_GENOMAS" "$E_PASTA_FASTA_GENOMAS" || return 1
    
    # Uso: rehydrate_selected_genomes <dir_genomas> <numero_conexoes> <download_gzip:true:false> <dir_fasta_genomas>
    rehydrate_selected_genomes "$A_DIR_GENOMAS" "$E_NUMERO_CONEXOES" "$E_DOWNLOAD_GZIP" "$E_PASTA_FASTA_GENOMAS" \
        || { echo_erro "Funcao rehydrate_selected_genomes falhou!"; return 1 ; }
            
    avancar_pipeline
}

# 6) Filtrar genomas com muitos gaps
etapa_6() {
    F_NUMERO_THREADS="$NUMERO_CPU" # threads = cpus
    F_DIR_QUALIDADE_SEQKIT="SEQKIT-RESULTS"
    F_LISTA_GENOMAS_FILTRADOS="lista-genomas-poucos-gaps.txt"
    F_TAMANHO_MINIMO_GAP="50" # Constantes do Prodigal (programa de anotacao)
	F_MAX_GAPS_PERMITIDO="5000" # Constantes do Prodigal (programa de anotacao)
    [ "$E_DOWNLOAD_GZIP" == "false" ] && F_EXTENSAO_ARQUIVO_GENOMA="fna"
    [ "$E_DOWNLOAD_GZIP" == "true" ] && F_EXTENSAO_ARQUIVO_GENOMA="gz"
	F_DIR_GENOMAS_INDESEJADOS="${E_PASTA_FASTA_GENOMAS}/REMOVED-GENOMES"
    
    
    executar_etapa 6 || return 0
    checar_argumentos -d "$E_PASTA_FASTA_GENOMAS" || return 1
        
    # [AVISO] Necessario remover genomas com muitos gaps para calculo do checkm2 (etapa 7)
    # CheckM2 tem uma etapa de anotacao com o Prodigal que dá erro em casos de genomas
    # com muitos gaps
    
    # filtrar_genomas_muitos_gaps <dir_fasta_genomas> <numero_cpus> <diretorio_output> <extensao_genomas:.fna:.gz>  
    # <lista_genomas_poucos_gaps> <tam_min_gap> <num_max_gaps>
    filtrar_genomas_muitos_gaps  "$E_PASTA_FASTA_GENOMAS" "$F_NUMERO_THREADS" \
    "$F_DIR_QUALIDADE_SEQKIT" "$F_EXTENSAO_ARQUIVO_GENOMA" "$F_LISTA_GENOMAS_FILTRADOS" \
    "$F_TAMANHO_MINIMO_GAP" "$F_MAX_GAPS_PERMITIDO" \
        || { echo_erro "Funcao filtrar_genomas_muitos_gaps falhou!"; return 1 ; }
        
    checar_argumentos -f "$F_LISTA_GENOMAS_FILTRADOS" || return 1
    
    # Uso: atualizar_tabelas_metadados <lista_genomas:coluna unica:sem HEADER:caminho/acesso do genoma> <dir_metadados_selecionados> <dir_metadados_removidos> <dir_metadados_originais:OPCIONAL>
    atualizar_tabelas_metadados "$F_LISTA_GENOMAS_FILTRADOS" \
    "$B_DIR_METADADOS_TSV" "$C_DIR_METADADOS_INDESEJADOS" \
        || { echo_erro "Funcao atualizar_tabelas_metadados falhou!" ; return 1 ; }
    
    # Uso: atualizar_pasta_genomas <lista_genomas> <pasta_genomas> <extensao_genoma> <dir_removed_genomes>
    atualizar_pasta_genomas "$F_LISTA_GENOMAS_FILTRADOS" \
    "$E_PASTA_FASTA_GENOMAS" "$F_EXTENSAO_ARQUIVO_GENOMA" "$F_DIR_GENOMAS_INDESEJADOS" \
        || { echo_erro "Funcao atualizar_pasta_genomas falhou!" ; return 1 ; }
        
    avancar_pipeline
}


# 7) Filtrar genomas pela qualidade do CheckM2
etapa_7() {
    G_NUMERO_THREADS="$NUMERO_CPU" # threads = cpus
    G_DIR_QUALIDADE_CHECKM2="CHECKM2-RESULTS"
    G_ARQUIVO_QUALIDADE_CHECKM2="${G_DIR_QUALIDADE_CHECKM2}/quality_report.tsv"
    G_MINIMO_COMPLETUDE="75" # Valor sugerido
    G_MAXIMO_CONTAMINACAO="5" # Valor sugerido
    G_LISTA_GENOMAS_ALTA_QUALIDADE="lista-genomas-alta-qualidade.txt"
    
    executar_etapa 7 || return 0
    checar_argumentos -d "$E_PASTA_FASTA_GENOMAS" || return 1
    
    # Uso: filtrar_genomas_pelo_checkm2 <dir_fasta_genomas> <numero_cpus> <diretorio_output> <extensao_arquivo_genomas:.fna:.gz> 
    # <min_completude> <max_contaminacao> <lista_genomas_alta_qualidade>
    filtrar_genomas_pelo_checkm2 "$E_PASTA_FASTA_GENOMAS" "$G_NUMERO_THREADS" \
    "$G_DIR_QUALIDADE_CHECKM2" "$F_EXTENSAO_ARQUIVO_GENOMA" \
    "$G_MINIMO_COMPLETUDE" "$G_MAXIMO_CONTAMINACAO" "$G_LISTA_GENOMAS_ALTA_QUALIDADE" \
        || { echo_erro "Funcao filtrar_genomas_pelo_checkm2 falhou!"; return 1 ; }
        
    checar_argumentos -f "$G_LISTA_GENOMAS_ALTA_QUALIDADE" || return 1
    
    # Uso: atualizar_tabelas_metadados <lista_genomas:coluna unica:sem HEADER:caminho/acesso do genoma> <dir_metadados_selecionados> <dir_metadados_removidos> <dir_metadados_originais:OPCIONAL>
    atualizar_tabelas_metadados "$G_LISTA_GENOMAS_ALTA_QUALIDADE" \
    "$B_DIR_METADADOS_TSV" "$C_DIR_METADADOS_INDESEJADOS" \
        || { echo_erro "Funcao atualizar_tabelas_metadados falhou!" ; return 1 ; }
    
    # Uso: atualizar_pasta_genomas <lista_genomas> <pasta_genomas> <extensao_genoma> <dir_removed_genomes>
    atualizar_pasta_genomas "$G_LISTA_GENOMAS_ALTA_QUALIDADE" \
    "$E_PASTA_FASTA_GENOMAS" "$F_EXTENSAO_ARQUIVO_GENOMA" "$F_DIR_GENOMAS_INDESEJADOS" \
        || { echo_erro "Funcao atualizar_pasta_genomas falhou!" ; return 1 ; }
    
    avancar_pipeline
}

# 8) Buscar classificao taxonomica dos genomas no GTDB
etapa_8() {
    H_LINK_BASE_GTDB="https://data.gtdb.aau.ecogenomic.org/releases/latest" # latest (06/2026): R232
    H_DIR_TAXONOMIA="TAXONOMY-DIRECTORY"
    H_TAXONOMIA_ARQUEIA_GZ="${H_DIR_TAXONOMIA}/ar53_taxonomy.tsv.gz"
    H_TAXONOMIA_BACTERIA_GZ="${H_DIR_TAXONOMIA}/bac120_taxonomy.tsv.gz"
    H_TABELA_TAXONOMIA="${H_DIR_TAXONOMIA}/TAXONOMY-TABLE.tsv"
    H_LISTA_GENOMAS_NAO_CLASSIFICADOS="${H_DIR_TAXONOMIA}/lista-genomas-nao-classificados.txt"
    
    executar_etapa 8 || return 0
    checar_argumentos -f "$D_METADADOS_GERAIS" || return 1
    
    # Uso: create_taxonomic_file <gtdb_link> <archaea_file> <bacteria_file>  <genome_curated_metadata>
    # <dir_output_tax> <output_genomes_tax> <output_list_non_classify_genomes>
    create_taxonomic_file "$H_LINK_BASE_GTDB" "$H_TAXONOMIA_ARQUEIA_GZ" "$H_TAXONOMIA_BACTERIA_GZ" \
    "$D_METADADOS_GERAIS" "$H_DIR_TAXONOMIA" "$H_TABELA_TAXONOMIA" "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS" \
        || { echo_erro "Funcao create_taxonomic_file falhou!"; return 1 ; }
          
    avancar_pipeline
}

# 9) Classificao taxonomica com GTDB-Tk dos genomas nao classificados
etapa_9() {
    I_NOME_PBS="Classificacao-Genomas-Restantes.pbs"
    I_NOME_JOB="GTDBTK-Classificacao"
    I_NUMERO_CPUS="4" # Aumento de velocidade ate 32 CPU
    I_MEMORIA_RAM="330" # Minimo de 140GB de RAM para classificacao com GTDB versao R232
    I_FILA_CLUSTER="high_mem"
    I_WALLTIME_MAX="2160:00:00"
    I_NUMERO_CPUS_PPLACER="1" # to tendo erro de gasto excessivo de RAM (chega a 380 GB RAM)
    I_DIR_OUTPUT_RESULTADOS_GTDBTK="GTDBTK-CLASSIFICATION"
    I_OUTPUT_TAXONOMIA_COMPLETA="${H_DIR_TAXONOMIA}/COMPLETE-TAXONOMY-TABLE.tsv"

    executar_etapa 9 || return 0
    checar_argumentos -f "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS" || return 1

    # Verificando o num de genomas nao classificados
    I_NUM_GENOMAS_NAO_CLASSIFICADOS=$(wc -l < "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS")
    if [[ "$I_NUM_GENOMAS_NAO_CLASSIFICADOS" -gt 0 ]]; then
        
        # Rodar a etapa em job-filho apenas se a execucao for em cluster de alto desempenho (HPC)
        if [[ -z "$LOCAL_EXECUCAO" ]]; then
            echo "[ERRO] Variavel LOCAL_EXECUCAO nao encontrada!" >> "$LOG_FILE"
            return 1
        fi
        if [[ "$LOCAL_EXECUCAO" == "cluster" ]]; then
            gerar_pbs_etapa_9 "$I_NOME_PBS" "$I_NOME_JOB" "$I_NUMERO_CPUS" "$I_MEMORIA_RAM" \
                "$I_FILA_CLUSTER" "$I_WALLTIME_MAX" "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS" \
                "$F_EXTENSAO_ARQUIVO_GENOMA" "$I_NUMERO_CPUS_PPLACER" "$I_DIR_OUTPUT_RESULTADOS_GTDBTK" \
                    || { echo_erro "Funcao gerar_pbs_etapa_9 falhou!" >> "$LOG_FILE"; return 1; }

            submeter_e_aguardar "$I_NOME_PBS" "$I_NOME_JOB" \
                || { echo_erro "Funcao submeter_e_aguardar falhou!" >> "$LOG_FILE"; return 1; }
        else
            # Por enquanto execucao do etapa 9, apenas para execucao no cluster
            echo "[WARNING] Execucao da classificao com GTDB-TK so pode ser feita no cluster" >> "$LOG_FILE"
            echo "[WARNING] Pulando etapa" >> "$LOG_FILE"
        fi
    fi
    
    checar_argumentos -f "$H_TABELA_TAXONOMIA" -d "$I_DIR_OUTPUT_RESULTADOS_GTDBTK" || return 1
    
    # Uso: update_taxonomy_file <taxonomy_file> <new_taxonomy_file> <gtdbtk_results_dir:OPCIONAL>
    update_taxonomy_file "$H_TABELA_TAXONOMIA" "$I_OUTPUT_TAXONOMIA_COMPLETA" "$I_DIR_OUTPUT_RESULTADOS_GTDBTK" \
        || { echo "Funcao update_taxonomy_file falhou!" >> "$LOG_FILE"; return 1; }

    avancar_pipeline
}

# 10) Criar estrutura de diretorios a partir da classificao taxonomica
etapa_10() {
    J_ESTRUTURA_DIR="TAXONOMY-DIRECTORY-STRUCTURE"
    J_DIRS_FOLHA_TODAS_ESPECIES="tabela-dir-todas-especies.tsv" # tabela com 2 colunas: 1° contem o caminho para o dir-folha e a segunda o numero de genomas dentro do diretorio

    executar_etapa 10 || return 0
    checar_argumentos -d "$A_DIR_GENOMAS" -f "$I_OUTPUT_TAXONOMIA_COMPLETA"  || return 1
    
    # Uso: create_taxonomic_dir_structure <taxonomy_file> <taxonomic_dir_struct_name> <pasta_genomas> <extensao_genoma>
    create_taxonomic_dir_structure "$I_OUTPUT_TAXONOMIA_COMPLETA" \
    "$J_ESTRUTURA_DIR" "$A_DIR_GENOMAS" "$F_EXTENSAO_ARQUIVO_GENOMA" \
        || { echo_erro "Funcao create_taxonomic_dir_structure falhou!" >> "$LOG_FILE"; return 1 ; }
    
    checar_argumentos -d "$J_ESTRUTURA_DIR" || return 1

    # Uso: <estrutura_dir_tax> <tabela_dir_folha>
    listar_dir_folha "$J_ESTRUTURA_DIR" "$J_DIRS_FOLHA_TODAS_ESPECIES" \
        || { echo_erro "Funcao listar_dir_folha falhou!" >> "$LOG_FILE"; return 1 ; }
        
    avancar_pipeline
}


# 11) Desreplicacao dos genomas (com filtragem do MGE temporaria)
etapa_11() {
    K_DIRS_FOLHA_REPRESENTATIVOS="tabela-dir-representativos.tsv" # 1° col: caminho para o dir-folha / 2° col: numero de genomas dentro do dir-folha
    K_LISTA_GENOMAS_REPRESENTATIVOS="lista-genomas-representativos.txt"
    K_PROGRAMA_FILTRAGEM_MGE="phispy" # genomad ou phispy
    
    executar_etapa 11 || return 0
    checar_argumentos -f "$J_DIRS_FOLHA_TODAS_ESPECIES" || return 1
    
    # # Uso: desreplicacao_no_dir_taxonomia <tabela_dir_folha> <max_memoria> <num_cpus> <extensao_genoma> <output_tabela_dir_folha_rep> <output_lista_genomas_rep> <programa_filtragem_mge>
    # desreplicacao_genomas "$J_DIRS_FOLHA_TODAS_ESPECIES" "$MEMORIA_RAM" "$NUMERO_CPU" "$F_EXTENSAO_ARQUIVO_GENOMA" "$K_DIRS_FOLHA_REPRESENTATIVOS" "$K_LISTA_GENOMAS_REPRESENTATIVOS" "$K_PROGRAMA_FILTRAGEM_MGE" || return 1
    
    # Uso: atualizar_tabelas_metadados <lista_genomas:coluna unica:sem HEADER:caminho/acesso do genoma> <dir_metadados_selecionados> <dir_metadados_removidos> <dir_metadados_originais:OPCIONAL>
    atualizar_tabelas_metadados "$K_LISTA_GENOMAS_REPRESENTATIVOS" \
    "$B_DIR_METADADOS_TSV" "$C_DIR_METADADOS_INDESEJADOS" \
        || { echo_erro "Funcao atualizar_tabelas_metadados falhou!" ; return 1 ; }
    
    # Uso: atualizar_pasta_genomas <lista_genomas> <pasta_genomas> <extensao_genoma> <dir_removed_genomes>
    atualizar_pasta_genomas "$K_LISTA_GENOMAS_REPRESENTATIVOS" \
    "$E_PASTA_FASTA_GENOMAS" "$F_EXTENSAO_ARQUIVO_GENOMA" "$F_DIR_GENOMAS_INDESEJADOS" \
        || { echo_erro "Funcao atualizar_pasta_genomas falhou!" ; return 1 ; }
    
    avancar_pipeline
}

# 13) Obter estatisticas dos genomas representativos sem mge (com seqkit)

# --- FUNÇÕES PARA VERIFICAR ARQ E DIR NO OUTPUT-DIR ---
arquivo_existe_no_output () {
    local ARQUIVO="${1?}"
    [ -f "${ARQUIVO}" ] || { echo "Arquivo '$ARQUIVO' nao encontrado em $(pwd)"  >> "$LOG_FILE" ; return 1 ; }
    return 0
}

diretorio_existe_no_output () {
    local DIRETORIO="${1?}"
    [ -d "${DIRETORIO}" ] || { echo "Diretorio '$DIRETORIO' nao encontrado em $(pwd)"  >> "$LOG_FILE" ; return 1 ; }
    return 0
}

# --- FUNÇÕES AUXILIARES ---
echo_erro () {
    local MENSAGEM="${@?}"
    local CALLER_FUNC="${FUNCNAME[1]:-main}"
    local DATA="$(date +"%H:%M:%S")"
    
    echo "[${DATA}] ERRO: Na etapa $(nome_etapa ${ETAPA_ATUAL})" >> "$LOG_FILE"
    echo "[${DATA}] ERRO: Na funcao ${CALLER_FUNC}" >> "$LOG_FILE"
    echo "[${DATA}] ERRO: ${MENSAGEM}" >> "$LOG_FILE"
}

save_step () {
	local STEP="${1?}"

    [ -f "$CHECKPOINT_FILE" ] || { echo_erro "Nao foi possivel salvar etapa $1: Arquivo de checkpoint $CHECKPOINT_FILE nao encontrado" ; return 1 ; }
    echo "$STEP" >> "$CHECKPOINT_FILE" 
}

get_last_step () {
	local FIRST_STEP="1"
    local CURRENT_STEP

    if [[ ! -f "$CHECKPOINT_FILE" ]]; then
        echo "Nao foi possivel recuperar ultima etapa: Arquivo de checkpoint $CHECKPOINT_FILE nao encontrado em $OUTPUT_DIR" >> "$LOG_FILE"
        echo "Criando novo arquivo $CHECKPOINT_FILE ..." >> "$LOG_FILE"
        echo "$FIRST_STEP" > "$CHECKPOINT_FILE"
    else
		echo "Dados do andamento do script encontrados em $(pwd)/${CHECKPOINT_FILE}" >> "$LOG_FILE"
	fi
    
    # Validar etapa atual antes de retornar com echo
    CURRENT_STEP="$(tail -n1 "$CHECKPOINT_FILE")"
    if [[ ! "$CURRENT_STEP" =~ ^[0-9]+$ ]]; then
        echo "[ERRO] Ultima linha do arquivo checkpoint.txt nao corresponde a uma etapa valida" >> "$LOG_FILE"
        echo "[ERRO] Certifique-se de que nao ha nenhuma linha em branco" >> "$LOG_FILE"
        echo "FIM DO SCRIPT" >> "$LOG_FILE"
        return 1
    fi
    echo "$CURRENT_STEP"
}

nome_etapa () {
    local ETAPA="${1?}"
    local INDICE_VETOR=$(( ETAPA-1 ))
    NOMES_ETAPAS=(
    "1) Download de genomas desidratados do NCBI"
    "2) Gerar tabelas de metadados formatados em TSV"
    "3) Filtragem dos genomas pelos metadados de qualidade dos genomas"
    "4) Identificacao de grupo extremofilico (como termofilo)"
    "5) Selecao e reidratacao dos genomas da categoria escolhida"
    "6) Filtrar genomas com muitos gaps"
    "7) Filtrar genomas pela qualidade do CheckM2"
    "8) Buscar classificao taxonomica dos genomas no GTDB"
    "9) Classificao taxonomica com GTDB-Tk dos genomas nao classificados"
    "10) Criar estrutura de diretorios a partir da classificao taxonomica"
    "11) Desreplicacao dos genomas com skDER"
    )
    
    echo "${NOMES_ETAPAS["$INDICE_VETOR"]}"
}

mensagem_etapa () {
	local ETAPA="${1?}"

	case "$ETAPA" in 
        
1)  # 1) Download de genomas desidratados do NCBI
cat << EOF >> "$LOG_FILE"

======== 1) DOWNLOAD DOS GENOMAS DESIDRATADOS ========

Parametros selecionados:
Taxon analisado: $TAXON_ANALISADO
Taxid analisado: $TAXID_ANALISADO
Banco de genomas: $A_BANCO_GENOMAS

Arquivos gerados no diretorio $OUTPUT_DIR
Diretorio de genomas desidratados: $A_DIR_GENOMAS

EOF
;; # ;; - para a execucao do case

2) # 2) Gerar tabelas de metadados formatados em TSV
cat << EOF >> "$LOG_FILE"

======== 2) GERAR TABELAS DE METADADOS FORMATADOS EM TSV ========"

Parametros selecionados:
Campos de metadados: $B_CAMPOS_METADADOS

Arquivos gerados no diretorio $OUTPUT_DIR
Diretorio com metadados: $B_DIR_METADADOS_TSV
Arquivo de metadados gerais: GENERAL-METADATA.tsv
Arquivo de metadados do assembly: ASSEMBLY-METADATA.tsv
Arquivo de metadados de qualidade: QUALITY-METADATA.tsv
Arquivo de metadados da amostra: SAMPLE-METADATA.tsv

EOF
;;

3) # 3) Filtragem dos genomas pelos metadados de qualidade dos genomas
cat << EOF >> "$LOG_FILE"

======== 3) FILTRAGEM DOS GENOMAS PELOS METADADOS DE QUALIDADE DOS GENOMAS ========

Parametros selecionados:
Numero de contigs maximo: $C_NUMERO_CONTIGS_MAX
Cobertura minima: $C_COBERTURA_MIN
N50 minimo: $C_N50_BP_MIN

Arquivos gerados no diretorio $OUTPUT_DIR
Lista de genomas selecionados: $C_LISTA_GENOMAS_FILTRADOS
Diretorio com os metadados filtrados:  $B_DIR_METADADOS_TSV
Diretorios com os metadados originais: $C_DIR_METADADOS_ORIGINAIS
Diretorios com os metadados removidos: $C_DIR_METADADOS_INDESEJADOS

EOF
;;

4) # 4) Identificacao de grupo extremofilico (como termofilo)
cat << EOF >> "$LOG_FILE"

======== 4) IDENTIFICANDO GENOMAS DA CATEGORIA SELECIONADA ========

Parametros selecionados:
Categoria: $D_CATEGORIA

Arquivos externos:
Fonte: $(realpath $D_DIR_DADOS)
Arquivo com taxid da categoria: ${D_VETOR_TABELAS_TAXID[@]}
Nome dos bancos com taxid: ${D_VETOR_NOME_TAXID[@]}
Coluna com taxid (em cada arquivo): ${D_VETOR_COLUNA_TAXID[@]}
Arquivo com fonte de isolamento da categoria: $D_ARQUIVO_FONTES_ISOLAMENTO

Arquivos gerados no diretorio $OUTPUT_DIR
Metadados filtrados com classificao da categoria: $D_METADADOS_CLASSIFICADOS
Metadados filtrados apenas da categoria: $D_METADADOS_APENAS_CATEGORIA

EOF
;;
    
5) # 5) Selecao e reidratacao dos genomas da categoria escolhida
cat << EOF >> "$LOG_FILE"

======== 5) REIDRATANDO GENOMAS DA CATEGORIA SELECIONADA ========

Parametros selecionados:
Numero de conexoes com server NCBI: $E_NUMERO_CONEXOES
Download compactado (em .gz): $E_DOWNLOAD_GZIP

Arquivos gerados no diretorio $OUTPUT_DIR
URL dos genomas da categoria: $E_ARQUIVO_URL_GENOMAS_CATEGORIA
Diretorio de genomas hidratados: $A_DIR_GENOMAS

EOF

;;
    
# Testar se o taxid pertence ao dominio Bacteria ou Archaea
# Os proximos programas estao destinados a procariotos
    
6) # 6) Filtrar genomas com muitos gaps
cat << EOF >> "$LOG_FILE"

======== 6) FILTRAR GENOMAS COM MUITOS GAPS ========

Parametros selecionados:
Numero de threads (CPU): $F_NUMERO_THREADS
Compactar arquivo FASTA: $E_DOWNLOAD_GZIP
Extensao do arquivo FASTA: $F_EXTENSAO_ARQUIVO_GENOMA
Tamanho minimo do GAP: $F_TAMANHO_MINIMO_GAP
Numero maximo de GAPS: $F_MAX_GAPS_PERMITIDO

Arquivos gerados no diretorio atual:
Diretorio com resultados do seqkit: $F_DIR_QUALIDADE_SEQKIT
Lista de genomas poucos gaps: $F_LISTA_GENOMAS_FILTRADOS

EOF
;;
    
7) # 7) Filtrar genomas pela qualidade do CheckM2
cat << EOF >> "$LOG_FILE"

======== 7) FILTRAR GENOMAS PELA QUALIDADE DO CHECKM2 ========

Parametro selecionados:
Numero de threads (CPU): $G_NUMERO_THREADS
Minimo de Completude: ${G_MINIMO_COMPLETUDE}%
Maximo de Contaminacao: ${G_MAXIMO_CONTAMINACAO}%

Arquivos gerados:
Diretorio com resultados do checkm2: $G_ARQUIVO_QUALIDADE_CHECKM2
Lista de genomas de alta qualidade: $G_LISTA_GENOMAS_ALTA_QUALIDADE

EOF
;;
    
8) # 8) Buscar classificao taxonomica dos genomas no GTDB
cat << EOF >> "$LOG_FILE"

======== 8) BUSCANDO CLASSIFICACAO TAXONOMICAO NO GTDB ========

Arquivos externos
Fonte: $H_LINK_BASE_GTDB
Taxonomia de arqueias: $H_TAXONOMIA_ARQUEIA_GZ
Taxonomia de bacterias: $H_TAXONOMIA_BACTERIA_GZ

Arquivos gerados:
Taxonomia do GTDB completa: gtdb_prokaryote_taxonomy.tsv
Taxonomia dos genomas: $H_TABELA_TAXONOMIA
Lista de genomas sem taxonomia: $H_LISTA_GENOMAS_NAO_CLASSIFICADOS

EOF
;;

# Execucao paralela em outra fila do cluster
# Fila: high_mem


9) # 9) Classificao taxonomica com GTDB-Tk dos genomas nao classificados 
cat << EOF >> "$LOG_FILE"

======== 9) CLASSIFICANDO TAXONOMICAMENTE GENOMAS COM GTDB-TK ========

Parametro selecionados
Numero de CPUs: $I_NUMERO_CPUS
Memoria RAM: $I_MEMORIA_RAM
Fila Cluster: $I_FILA_CLUSTER
Walltime Maximo: $I_WALLTIME_MAX
Numero de CPUs para pplacer: $I_NUMERO_CPUS_PPLACER

Arquivos gerados:
Taxonomia gerada pelo GTDBTK: $I_DIR_OUTPUT_RESULTADOS_GTDBTK
Taxonomia dos genomas completa: $I_OUTPUT_TAXONOMIA_COMPLETA

EOF
;;

10) # 10) Criar estrutura de diretorios a partir da classificao taxonomica
cat << EOF >> "$LOG_FILE"

======== 10) CRIANDO ESTRUTURA DE DIRETORIOS COM A TAXONOMIA ========

Arquivos gerados
Estrutura de diretorios para taxonomia: $J_ESTRUTURA_DIR
Tabela com dirs das especies: $J_DIRS_FOLHA_TODAS_ESPECIES

EOF
;;
    
11) # 11) - Filtragem de elementos geneticos moveis (MGE)
cat << EOF >> "$LOG_FILE"

======== 11) DESREPLICACAO DOS GENOMAS COM SKDER ========

Parametros selecionados
Programa para filtragem de MGE: $K_PROGRAMA_FILTRAGEM_MGE
Tipo de desreplicacao no skder: greedy

Arquivos gerados
Tabela de dir-folha de genomas representativos: $K_DIRS_FOLHA_REPRESENTATIVOS
Lista de genomas representativos: $K_LISTA_GENOMAS_REPRESENTATIVOS

EOF
;;

12) # 12) - Desreplicacao dos genomas sem MGE
cat << EOF >> "$LOG_FILE"

======== 12) NAO SEI ========

Parametros selecionados


EOF
;;

    esac
}

# --- EXECUÇÃO PRINCIPAL DO PIPELINE ---



# Chamada da funcao: create_curated_database <taxon_analisado> <taxid_analisado=OPCIONAL>


create_curated_database () {

    # 1. Carregando as variaveis gerais do script
    TAXON_ANALISADO="${1?}"
    TAXID_ANALISADO="$2" # ARGUMENTO OPCIONAL
    NOME_BASE="${TAXON_ANALISADO}-GENOMES"
    LOG_FILE="$(realpath "$LOG_FILE")"
    CHECKPOINT_FILE="checkpoint.txt" # A ultima etapa é a etapa atual
    
    # 2. Funcao verifica arquivo de checkpoint para a execucao continuar de onde parou 
    ETAPA_ATUAL="$(get_last_step || return 1)"
	echo "Script iniciando na etapa ${ETAPA_ATUAL}: $(nome_etapa ${ETAPA_ATUAL})" >> "$LOG_FILE"

    
    # 3. Chamada das funcoes da pipeline
    # Se qualquer funcao falhar, o operador '&&' interrompe o fluxo imediatamente.
    etapa_1  && \
    etapa_2  && \
    etapa_3  && \
    etapa_4  && \
    etapa_5  && \
    etapa_6  && \
    etapa_7  && \
    etapa_8  && \
    etapa_9  && \
    etapa_10 && \
    etapa_11 && echo "Pipeline finalizado com sucesso!" || echo_erro "O pipeline parou devido a um erro."

}


# # 11) Filtragem de elementos geneticos moveis (MGE)
# etapa_11() {
    # K_DIRS_FOLHA_SEM_MGE="tabela-dir-sem-mge.tsv"  # tabela com 2 colunas: 1° contem o caminho para o dir-folha-sem-mge e a segunda o numero de genomas dentro do diretorio
    
    # executar_etapa 11 || return 0
    # checar_argumentos -f "$J_DIRS_FOLHA_TODAS_ESPECIES" || return 1
    
    # # Uso: <lista_dir_folha> <extensao_genoma> <programa_filtragem_mge> <lista_dir_folha_sem_mge> <numero_cpu>
    # filtrar_mge_genomas "$J_DIRS_FOLHA_TODAS_ESPECIES" "$F_EXTENSAO_ARQUIVO_GENOMA"  \
    # "$K_PROGRAMA_FILTRAGEM_MGE" "$K_DIRS_FOLHA_SEM_MGE" "$NUMERO_CPU" \
        # || { echo_erro "Funcao filtrar_mge_genomas falhou!" ; return 1 ; }
    
    # avancar_pipeline
# }