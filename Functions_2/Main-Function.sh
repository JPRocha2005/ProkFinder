# Funcao geral para criação do banco de dados curado

# Chamada da funcao: create_curated_database <taxon_analisado> <taxid_analisado=OPCIONAL>

create_curated_database () {

    # 0) Ajustando os parametros gerais da funcao
    TAXON_ANALISADO="${1?}"
    TAXID_ANALISADO="$2" # ARGUMENTO OPCIONAL
    NOME_BASE="${TAXON_ANALISADO}-GENOMES"
    LOG_FILE="$(realpath "$LOG_FILE")"
    [ -f "$LOG_FILE" ] || { echo "[ERRO] Arquivo $LOG_FILE nao existe" >&2 ; return 1 ; } 

    echo "Iniciando funcao principal para execucao do programa" >> "$LOG_FILE"

    # Buscar o taxid do taxon utilizando o taxonkit
    if [[ -z "$TAXID_ANALISADO" ]]; then
        echo "Buscando taxid do taxon $TAXON_ANALISADO com taxonkit v.0.20.0" >> "$LOG_FILE"
        local RESULTADO_TAXONKIT="$(echo "${TAXON_ANALISADO//_/ }" | taxonkit name2taxid 2>> "$LOG_FILE")"
        local NUMERO_LIN="$(echo "$RESULTADO_TAXONKIT" | wc -l)"
        local TAXONKIT_TAXID="$(echo "$RESULTADO_TAXONKIT" | awk -F'\t' '{print $2}')"
        if [[ "$NUMERO_LIN" -gt 1 ]]; then
            echo "[ERRO] Multiplos taxid encontrados para $TAXON_ANALISADO" >> "$LOG_FILE"
            echo "[ERRO] Especifique o taxid de interesse na chamada com script (flag --taxid)" >> "$LOG_FILE"
            return 1
        fi
        if [[ -z "$TAXONKIT_TAXID" ]]; then
            echo "[ERRO] Taxid nao encontrado para $TAXON_ANALISADO" >> "$LOG_FILE"
            echo "[ERRO] Especifique o taxid de interesse na chamada com script (flag --taxid)" >> "$LOG_FILE"
            return 1
        fi
        TAXID_ANALISADO="$TAXONKIT_TAXID"
        echo "TAXID encontrado para $TAXON_ANALISADO: $TAXID_ANALISADO" >> "$LOG_FILE"
    else
        echo "TAXID informado para $TAXON_ANALISADO: $TAXID_ANALISADO" >> "$LOG_FILE"
    fi

    # 1) Download de genomas desidratados do NCBI
    A_BANCO_GENOMAS="GenBank" # GenBank ou RefSeq (default - GenBank)
    A_DIR_GENOMAS="DIRECTORY-${NOME_BASE}"

    # 1.1) Verificando argumentos
    if [[ "$A_BANCO_GENOMAS" != "RefSeq" ]]; then
        A_BANCO_GENOMAS="GenBank"
    fi

    # 1.2) Imprimindo o bloco de execucao no arquivo log
cat << EOF >> "$LOG_FILE"

======== 1) DOWNLOAD DOS GENOMAS DESIDRATADOS ========

Parametros selecionados:
Taxon analisado: $TAXON_ANALISADO
Taxid analisado: $TAXID_ANALISADO
Banco de genomas: $A_BANCO_GENOMAS

Arquivos gerados no diretorio $OUTPUT_DIR
Diretorio de genomas desidratados: $A_DIR_GENOMAS

EOF

    # 1.3) Chamando a funcao
    # Uso: download_genomes_by_taxid <numero_taxid> <banco_dados> <output_dir_genomas>

    download_genomes_by_taxid "$TAXID_ANALISADO" "$A_BANCO_GENOMAS" \
    "$A_DIR_GENOMAS" || return 1
    
    # 1.4) Resultados
    arquivo_existe_no_output "$A_DIR_GENOMAS/ncbi_dataset/data/assembly_data_report.jsonl" || return 1
	A_ARQUIVO_METADADOS="$A_DIR_GENOMAS/ncbi_dataset/data/assembly_data_report.jsonl"
    A_NUMERO_GENOMAS="$(contar_genomas "$A_ARQUIVO_METADADOS" --no_header)"
    if [[ "$A_NUMERO_GENOMAS" -eq 0 ]]; then
		echo "[ERRO] Nenhum genoma encontrado para o taxid '$TAXID_ANALISADO' ($TAXON_ANALISADO)" >> "$LOG_FILE"
		echo "[ERRO] Verifique se o taxid '$TAXID_ANALISADO' nao esta invalido" >> "$LOG_FILE"
		return 1
	fi
	echo "Numero de genomas baixados: $A_NUMERO_GENOMAS" >> "$LOG_FILE"

    # 2) Conversao dos metadados de JSON para TSV
    B_METADADOS_GENOMAS_JSON="${A_DIR_GENOMAS}/ncbi_dataset/data/assembly_data_report.jsonl"
    B_CAMPOS_METADADOS="accession,organism-tax-id,assminfo-biosample-isolation-source" 
    B_METADADOS_SELECIONADOS_TSV="METADATA-${NOME_BASE}.tsv"
    B_METADADOS_COMPLETOS_TSV="COMPLETE-${B_METADADOS_SELECIONADOS_TSV}"

    # 2.1) Verificando arquivos
    CAMPOS_OBRIGATORIOS=("accession" "organism-tax-id" "assminfo-biosample-isolation-source")
    for campo in "${CAMPOS_OBRIGATORIOS[@]}"; do
        if [[ "$B_CAMPOS_METADADOS" != *"$campo"* ]]; then
            echo "[ERRO] Esta faltando o campo de metadado obrigatorio: $campo. Verifique o script" >> "$LOG_FILE"
            return 1
        fi
    done

    # 2.2) Imprimindo o bloco de execucao no arquivo log
cat << EOF >> "$LOG_FILE"

======== 2) CONVERSAO DO METADADOS EM JSON PARA TSV ========"

Parametros selecionados:
Campos de metadados: $B_CAMPOS_METADADOS

Arquivos gerados no diretorio $OUTPUT_DIR
Metadados com campos selecionados: $B_METADADOS_SELECIONADOS_TSV
Metadados com todos os campos: $B_METADADOS_COMPLETOS_TSV

EOF
      
    # 2.3) Chamando a funcao  

    # Uso: convert_metadata_to_tsv <input_metadados_jsonl> <campos_selecionados_separados_virgula> <dir_genomas_desidratados> <output_metadados_tsv>

    convert_metadata_to_tsv "$B_METADADOS_GENOMAS_JSON" "$B_CAMPOS_METADADOS" \
    "$A_DIR_GENOMAS" "$B_METADADOS_SELECIONADOS_TSV" || return 1
    create_complete_taxonomy_file "$B_METADADOS_GENOMAS_JSON" \
    "$A_DIR_GENOMAS" "$B_METADADOS_COMPLETOS_TSV" || return 1
    
    # 2.4) Resultados
    arquivo_existe_no_output "$B_METADADOS_SELECIONADOS_TSV" || return 1
    arquivo_existe_no_output "$B_METADADOS_COMPLETOS_TSV" || return 1

    # 3) Filtragem dos metadados
    C_METADADOS_SELECIONADOS_FILTRADOS="FILTERED-${B_METADADOS_SELECIONADOS_TSV}"
    C_METADADOS_COMPLETOS_FILTRADOS="FILTERED-${B_METADADOS_COMPLETOS_TSV}"
    C_VALOR_NULO_CELULAS="NULL"

    # 3.1) Verificando argumentos
    if [[ "$A_BANCO_GENOMAS" == "GenBank" ]]; then 
        C_PREFIXO_NOME_GENOMA="GCA_"
    else # "$A_BANCO_GENOMAS" == "RefSeq"
        C_PREFIXO_NOME_GENOMA="GCF_" 
    fi

    # 3.2) Imprimindo o bloco de execucao no arquivo log
cat << EOF >> "$LOG_FILE"

======== 3) FILTRAGEM DOS METADADOS ========

Parametros selecionados:
Valor nulo das celulas: $C_VALOR_NULO_CELULAS
Banco de genomas: $A_BANCO_GENOMAS
Prefixo do banco: $C_PREFIXO_NOME_GENOMA

Arquivos gerados no diretorio $OUTPUT_DIR
Metadados filtrados (campos selecionados): $C_METADADOS_SELECIONADOS_FILTRADOS
Metadados filtrados (todos os campos): $C_METADADOS_COMPLETOS_FILTRADOS

EOF

    # 3.3) Chamando a funcao

    # Uso: filter_metadata_tsv <input_metadado_nao_filtrados> <prefixo_escolhido> <valor_nulo> <output_metadados_filtrados>

    filter_metadata_tsv "$B_METADADOS_SELECIONADOS_TSV" "$C_PREFIXO_NOME_GENOMA" \
    "$C_VALOR_NULO_CELULAS" "$C_METADADOS_SELECIONADOS_FILTRADOS" || return 1
    filter_metadata_tsv "$B_METADADOS_COMPLETOS_TSV" "$C_PREFIXO_NOME_GENOMA" \
    "$C_VALOR_NULO_CELULAS" "$C_METADADOS_COMPLETOS_FILTRADOS" || return 1

    # 3.4) Resultados
    arquivo_existe_no_output "$C_METADADOS_SELECIONADOS_FILTRADOS" || return 1
    arquivo_existe_no_output "$C_METADADOS_COMPLETOS_FILTRADOS" || return 1
    echo "Numero de genomas apos filtragem: $(contar_genomas "$C_METADADOS_SELECIONADOS_FILTRADOS")" >> "$LOG_FILE"

    # 4) Identificacao de grupo extremofilico (como termofilo)
    D_DIR_DADOS="$(realpath ../../data)"
    D_VETOR_TABELAS_TAXID=( "pubmed-literature.tsv"  "MODIFIED-bacdive-thermophile-strains.tsv" "MODIFIED-tempura.tsv" "MODIFIED-thermobase.tsv" )
    D_VETOR_NOME_TAXID=( "LITERATURE" "BACDIVE" "TEMPURA" "THERMOBASE")
    D_VETOR_COLUNA_TAXID=( 2 3 3 3 )
    D_ARQUIVO_FONTES_ISOLAMENTO="isolation-source.txt" # precisam conter o taxid e ser tsv
    D_CATEGORIA="THERMOPHILIC" # identificacao / categorizacao / label nos genomas
    D_OUTPUT_METADADOS_CATEGORIA="${D_CATEGORIA}-${NOME_BASE}-METADATA.tsv" # todos os metadados com a identificacao do grupo
    D_OUTPUT_APENAS_METADADOS_CATEGORIA="ONLY-${D_CATEGORIA}-${NOME_BASE}-METADATA.tsv" # apenas os metadados com a identificacao do grupo nao nula

    # 4.1) Verficando argumentos
    ARGS_TABELAS=${#D_VETOR_TABELAS_TAXID[@]}
    ARGS_NOMES=${#D_VETOR_NOME_TAXID[@]}
    ARGS_COLUNS=${#D_VETOR_COLUNA_TAXID[@]}

    if [[ !( "$ARGS_TABELAS" -eq "$ARGS_NOMES" && "$ARGS_NOMES" -eq "$ARGS_COLUNS" ) ]]; then
        {
            echo "[ERRO] Os vetores com as referencias para identificacao de ${D_CATEGORIA} têm numero de argumentos diferentes."
            echo "-> Tabelas: $ARGS_TABELAS"
            echo "-> Nomes:   $ARGS_NOMES"
            echo "-> Colunas: $ARGS_COLUNS"
            echo "Cheque o script."
        } >> "$LOG_FILE"
        return 1
    fi
    if [[ ! -d "${D_DIR_DADOS}" ]]; then
        echo "[ERRO] Diretorio com os dados de identificacao $(basename ${D_DIR_DADOS}) nao encontrado!" >> "$LOG_FILE"
        return 1
    fi
    for TABLE in "${D_VETOR_TABELAS_TAXID[@]}" "$D_ARQUIVO_FONTES_ISOLAMENTO"; do
        if [[ ! -f "${D_DIR_DADOS}/${TABLE}" ]]; then
            echo "[ERROR] Arquivo de identificacao ${TABLE} nao encontrado" >> "$LOG_FILE"
            return 1
        fi
    done

    # 4.2) Imprimindo o bloco de execucao no arquivo log
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
Metadados filtrados com classificao da categoria: $D_OUTPUT_METADADOS_CATEGORIA
Metadados filtrados apenas da categoria: $D_OUTPUT_APENAS_METADADOS_CATEGORIA

EOF

    # 4.3) Chamando a funcao

    # Uso (NAO deve-se expandir os vetores com $, isso ira passar apenas o 1° elemento):
    # add_category_metadata <input_nao_categorizado> <diretorio_dados_referencia> <vetor_tabelas_dados> <vetor_nome_tabelas> <vetor_coluna_taxid> <fontes_isolamento> <categoria> <valor_nulo> <output_categorizado> <output_apenas_categorizados>

    add_category_metadata "$C_METADADOS_SELECIONADOS_FILTRADOS" "$D_DIR_DADOS" \
    D_VETOR_TABELAS_TAXID D_VETOR_NOME_TAXID D_VETOR_COLUNA_TAXID \
    "$D_ARQUIVO_FONTES_ISOLAMENTO" "$D_CATEGORIA" "$C_VALOR_NULO_CELULAS" \
    "$D_OUTPUT_METADADOS_CATEGORIA" "$D_OUTPUT_APENAS_METADADOS_CATEGORIA" || return 1
    
    # 4.4) Resultados
    arquivo_existe_no_output "$D_OUTPUT_METADADOS_CATEGORIA" || return 1
    arquivo_existe_no_output "$D_OUTPUT_APENAS_METADADOS_CATEGORIA" || return 1    
    echo "Numero de genomas da categoria $D_CATEGORIA: $(contar_genomas "$D_OUTPUT_APENAS_METADADOS_CATEGORIA")" >> "$LOG_FILE"

    # 5) Selecao e reidratacao dos genomas da categoria escolhida
    E_URL_GENOMAS="${A_DIR_GENOMAS}/ncbi_dataset/fetch.txt"
    E_URL_GENOMAS_CATEGORIA="${A_DIR_GENOMAS}/ncbi_dataset/fetch-${D_CATEGORIA}.txt"
    E_NUMERO_CONEXOES=10 # numero de requisicoes simultaneas para server do NCBI
    E_DOWNLOAD_GZIP="true"
    E_PASTA_FASTA_GENOMAS="${A_DIR_GENOMAS}/ncbi_dataset/data"

    # 5.1) Verificando argumentos
    arquivo_existe_no_output "$E_URL_GENOMAS" || return 1
    diretorio_existe_no_output "$E_PASTA_FASTA_GENOMAS" || return 1

    # 5.2) Imprimindo o bloco de execucao no arquivo log
cat << EOF >> "$LOG_FILE"

======== 5) REIDRATANDO GENOMAS DA CATEGORIA SELECIONADA ========

Parametros selecionados:
Numero de conexoes com server NCBI: $E_NUMERO_CONEXOES
Download compactado (em .gz): $E_DOWNLOAD_GZIP

Arquivos gerados no diretorio $OUTPUT_DIR
URL dos genomas da categoria: $E_URL_GENOMAS_CATEGORIA
Diretorio de genomas hidratados: $A_DIR_GENOMAS

EOF

    # 5.3) Chamando as funcoes

    # Uso: update_genomes_url_file <fetch.txt original> <metadados_categoria> <fetch.txt categoria> <categoria>
    # rehydrate_selected_genomes <dir_genomas> <numero_conexoes> <download_gzip:true:false> <dir_fasta_genomas>

    update_genomes_url_file "$E_URL_GENOMAS" "$D_OUTPUT_APENAS_METADADOS_CATEGORIA" \
    "$E_URL_GENOMAS_CATEGORIA" "$D_CATEGORIA" || return 1
    rehydrate_selected_genomes "$A_DIR_GENOMAS" "$E_NUMERO_CONEXOES" \
    "$E_DOWNLOAD_GZIP" "$E_PASTA_FASTA_GENOMAS" || return 1
    
    # 5.4) Resultados
    
    # 6) Calculo do CheckM2 dos genomas (so funciona para procariotos)
    F_NUMERO_THREADS="$NUMERO_CPU" # threads = cpus
    F_DIR_QUALIDADE_CHECKM2="CHECKM2-RESULTS-${NOME_BASE}"
    F_ARQUIVO_QUALIDADE_CHECKM2="${F_DIR_QUALIDADE_CHECKM2}/quality_report.tsv"
    F_EXTENSAO_ARQUIVO_GENOMA="fna" # padrao

    # 6.1) Verificando argumentos
    if [[ "$E_DOWNLOAD_GZIP" == "true" ]]; then
        F_EXTENSAO_ARQUIVO_GENOMA="gz"
    fi

    # 6.2) Imprimindo o bloco de execucao no arquivo log
cat << EOF >> "$LOG_FILE"

======== 6) CALCULANDO A QUALIDADE COM CHECKM2 ========

Parametros selecionados:
Numero de threads (CPU): $F_NUMERO_THREADS
Compactar arquivo FASTA: $E_DOWNLOAD_GZIP
Extensao do arquivo FASTA: $F_EXTENSAO_ARQUIVO_GENOMA

Arquivos gerados no diretorio atual:
Diretorio com resultados do checkm2: $F_DIR_QUALIDADE_CHECKM2
Resultados do checkm2: $F_ARQUIVO_QUALIDADE_CHECKM2

EOF


    echo "[WARNING] O calculo de qualidade de genomas utilizando o CheckM2 funciona apenas para organismos procariotos!" >> "$LOG_FILE"

    # Chamada da funcao
    # Uso: calcular_qualidade_genomas <dir_fasta_genomas> <numero_cpus> <diretorio_output> <extensao_arquivo_genomas:.fna:.gz> 

    calcular_qualidade_genomas "$E_PASTA_FASTA_GENOMAS" "$F_NUMERO_THREADS" \
    "$F_DIR_QUALIDADE_CHECKM2" "$F_EXTENSAO_ARQUIVO_GENOMA" || return 1
    
    # 6.4) Resultados
    ###

    # 7) Selecionar os metadados e os genomas de alta qualidade
    G_MINIMO_COMPLETUDE="75" # valor numerico
    G_MAXIMO_CONTAMINACAO="5" # valor numerico
    G_OUTPUT_METADADOS_ALTA_QUALIDADE="HIGH-QUALITY-${NOME_BASE}.tsv" # output
    G_DIR_GENOMAS_ALTA_QUALIDADE="HIGH-QUALITY-HYDRATED-${NOME_BASE}"

    # 7.2) Imprimindo o bloco de execucao no arquivo log
cat << EOF >> "$LOG_FILE"

======== 7) SELECIONANDO GENOMAS DE ALTA QUALIDADE ========

Parametro selecionados:
Minimo de Completude: ${G_MINIMO_COMPLETUDE}%
Maximo de Contaminacao: ${G_MAXIMO_CONTAMINACAO}%

Arquivos gerados:
Metadados de alta qualidade: $G_OUTPUT_METADADOS_ALTA_QUALIDADE
Diretorio com genomas de alta qualidade: $G_DIR_GENOMAS_ALTA_QUALIDADE

EOF

    # 7.3) Chamando as funcoes

    # Uso: selecionar_metadados_alta_qualidade <input_qualidade_checkm2> <metadados_da_categoria> <min_completude> <max_contaminacao> <output_metadados_alta_qualidade>
    # Uso: selecionar_genomas_alta_qualidade <input_metadados_alta_qualidade> <dir_genomas_da_categoria> <extensao_fasta> <maximo_cpus> <output_dir_genomas_alta_qualidade>

    selecionar_metadados_alta_qualidade  "$F_ARQUIVO_QUALIDADE_CHECKM2" \
    "$D_OUTPUT_APENAS_METADADOS_CATEGORIA" "$G_MINIMO_COMPLETUDE" \
    "$G_MAXIMO_CONTAMINACAO" "$G_OUTPUT_METADADOS_ALTA_QUALIDADE" || return 1

    selecionar_genomas_alta_qualidade "$G_OUTPUT_METADADOS_ALTA_QUALIDADE" \
    "$E_PASTA_FASTA_GENOMAS" "$F_EXTENSAO_ARQUIVO_GENOMA" \
    "$F_NUMERO_THREADS" "$G_DIR_GENOMAS_ALTA_QUALIDADE" || return 1
     
    # 7.4) Resultados
    arquivo_existe_no_output "$G_OUTPUT_METADADOS_ALTA_QUALIDADE"
    diretorio_existe_no_output "$G_DIR_GENOMAS_ALTA_QUALIDADE"
    echo "Numero de genomas de alta qualidade: $(contar_genomas "$G_OUTPUT_METADADOS_ALTA_QUALIDADE")" >> "$LOG_FILE"

    # 8) Buscar classificao taxonomica dos genomas no GTDB
    H_LINK_BASE_GTDB="https://data.gtdb.aau.ecogenomic.org/releases/latest" # latest (06/2026): R232
    H_TAXONOMIA_ARQUEIA_GZ="ar53_taxonomy.tsv.gz"
    H_TAXONOMIA_BACTERIA_GZ="bac120_taxonomy.tsv.gz"
    H_OUTPUT_TAXONOMIA="TAXONOMY-${NOME_BASE}.tsv"
    H_LISTA_GENOMAS_NAO_CLASSIFICADOS="NOT-CLASSIFIED-${NOME_BASE}.txt"
    H_LISTA_CAMINHO_GENOMAS_NAO_CLASSIFICADOS="NOT-CLASSIFIED-FASTA-PATH.txt"

    # 8.1) Verificando argumentos

    # 8.2) Imprimindo o bloco de execucao no log
cat << EOF >> "$LOG_FILE"

======== 8) BUSCANDO CLASSIFICACAO TAXONOMICAO NO GTDB ========

Arquivos externos
Fonte: $H_LINK_BASE_GTDB
Taxonomia de arqueias: $H_TAXONOMIA_ARQUEIA_GZ
Taxonomia de bacterias: $H_TAXONOMIA_BACTERIA_GZ

Arquivos gerados:
Taxonomia do GTDB completa: gtdb_prokaryote_taxonomy.tsv
Taxonomia dos genomas: $H_OUTPUT_TAXONOMIA
Lista de genomas sem taxonomia: $H_LISTA_GENOMAS_NAO_CLASSIFICADOS
Caminho para o FASTA dos genomas sem taxonomia: $H_LISTA_CAMINHO_GENOMAS_NAO_CLASSIFICADOS

EOF

    # 8.3) Chamando a funcao

    # Uso: create_taxonomic_file <gtdb_link> <archaea_file> <bacteria_file>  <genome_curated_metadata> <output_genomes_tax> <output_list_non_classify_genomes>

    create_taxonomic_file "$H_LINK_BASE_GTDB" "$H_TAXONOMIA_ARQUEIA_GZ" \
    "$H_TAXONOMIA_BACTERIA_GZ" "$G_OUTPUT_METADADOS_ALTA_QUALIDADE" \
    "$H_OUTPUT_TAXONOMIA" "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS" || return 1
    
    # 8.4) Resultados
    arquivo_existe_no_output "$H_OUTPUT_TAXONOMIA" || return 1
    arquivo_existe_no_output "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS" || return 1
    echo "Numero de genomas classificados pelo GTDB: $(contar_genomas "$H_OUTPUT_TAXONOMIA")" >> "$LOG_FILE"
    echo "Numero de genomas restantes: $(contar_genomas "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS" --no_header)" >> "$LOG_FILE"
    
    H_NUM_GENOMAS_NAO_CLASSIFICADOS="$(contar_genomas "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS")"
    
    # Guardando caminhos dos genomas nao classificados
    > "$H_LISTA_CAMINHO_GENOMAS_NAO_CLASSIFICADOS"
    
    if [[ "$H_NUM_GENOMAS_NAO_CLASSIFICADOS" -gt 0 ]] && [[ -f "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS" ]] ; then
        find "${A_DIR_GENOMAS%/}/ncbi_dataset/data" -type f -name "*.${F_EXTENSAO_ARQUIVO_GENOMA}" \
        | grep -F -f "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS" \
        >> "$H_LISTA_CAMINHO_GENOMAS_NAO_CLASSIFICADOS"
    fi
    
    # TRAVAR A EXECUCAO (POR ENQUANTO):
    H_NUM_GENOMAS_NAO_CLASSIFICADOS=0
   

if [[ "$H_NUM_GENOMAS_NAO_CLASSIFICADOS" -gt 0 ]]; then

    ############# ETAPA 9 - SUBMETER NOVO JOB COM MAIS CPU e RAM ##############

    # 9) Classificao taxonomica com GTDB-Tk dos genomas nao classificados 

    I_NOME_PBS="Classificacao-Genomas-Restantes.pbs"
    I_NOME_JOB="GTDBTK-Classificacao"
    I_NUMERO_CPUS="12" # A velocidade aumenta se colocar ate 32 CPUs, mas pode nao haver CPU disponivel no cluster
    I_MEMORIA_RAM="140" #  Minimo de 140GB de RAM para R232
    I_FILA_CLUSTER="high_mem"
    I_WALLTIME_MAX="2160:00:00"
    I_NUMERO_CPUS_PPLACER="2" # Pouca CPU para evitar que o limite de RAM seja ultrapassado 
    I_DIR_OUTPUT_RESULTADOS_GTDBTK="GTDB-CLASSIFICATION-${NOME_BASE}"
    I_OUTPUT_TAXONOMIA_COMPLETA="COMPLETE-TAXONOMY-${NOME_BASE}.tsv" # concatenacao da duas tabelas acima com a taxonomia adicionada na de baixo

    # 9.1) Verificando argumentos

    # 9.2) Imprimindo o bloco de execucao no log
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
    
    # 9.3) Escrevendo o script PBS para submissao em novo no
cat << 'EOF' >> "$I_NOME_PBS"
#!/usr/bin/env bash

# Mudando para o diretorio em que o PBS foi submetido (comando qsub)
cd "${PBS_O_WORKDIR}" || exit
source "/etc/profile.d/modules.sh"

# Ajustando caminho de LOG_FILE
LOG_FILE="$(realpath "${OUTPUT_DIR}/$LOG_FILE")"

# Carregar modulos externos
module load ncbi_datasets/18.26.0 taxonkit/0.20.0 checkm2/1.1.0 gtdbtk/2.7.2 \
|| { echo "Nao foi possivel carregar os modulos externos" >> "$LOG_FILE" ; exit 1 ; }
    
# Carregando modulos
DIR_MODULOS="Functions_2"
FUNCAO_PRINCIPAL="Main-Function.sh"
MODULOS_EXECUCAO=( "9_Find-Missing-Taxonomy.sh" )
if [[ ! -d "$DIR_MODULOS" ]]; then
    { echo "[ERRO] Diretorio $DIR_MODULOS nao foi encontrado!" >> "$LOG_FILE" ; exit 1 ; }
fi
for modulo in "$FUNCAO_PRINCIPAL" "${MODULOS_EXECUCAO[@]}"; do
    [[ -z "$modulo" ]] && { echo "Variavel modulo esta vazia: 'modulo'" >> "$LOG_FILE" ; exit 1 ; }
    caminho_modulo="${DIR_MODULOS}/${modulo}"
    if [[ -f "$caminho_modulo" ]]; then
        source "$caminho_modulo" || { echo "[ERRO] Na execucao do modulo $modulo em $DIR_MODULOS!" >> "$LOG_FILE" ; exit 1 ; }
    else
        echo "[ERRO] Modulo $caminho_modulo nao foi encontrado em $(pwd)!" >> "$LOG_FILE"
        exit 1
    fi
done

# Mudando para o diretorio de resultados
cd "$OUTPUT_DIR" || { echo "[ERRO] Nao foi possivel mudar para dir $OUTPUT_DIR" >> "$LOG_FILE" ; exit 1 ; } 
echo "[AVISO] Execucao do script sera feita dentro de $OUTPUT_DIR" >> "$LOG_FILE" 

# 9.4) Chamando a funcao

# Uso: classify_genomes <list_non_classified_genomes> <genomes_extension> <number_of_cpus> <number_of_cpus_for_pplacer> <output_dir_tax_classication>
# Uso: update_taxonomy_file <taxonomy_file> <gtdbtk_results_dir> <new_taxonomy_file>

classify_genomes "$H_LISTA_GENOMAS_NAO_CLASSIFICADOS" "$F_EXTENSAO_ARQUIVO_GENOMA" "$I_NUMERO_CPUS" "$I_NUMERO_CPUS_PPLACER" "$I_DIR_OUTPUT_RESULTADOS_GTDBTK" || { echo "Funcao classify_genomes falhou!" >> "$LOG_FILE" ; exit 1 ; }
update_taxonomy_file "$H_OUTPUT_TAXONOMIA" "$I_DIR_OUTPUT_RESULTADOS_GTDBTK" "$I_OUTPUT_TAXONOMIA_COMPLETA" || { echo "Funcao update_taxonomy_file falhou!" >> "$LOG_FILE" ; exit 1 ; }

EOF

    echo "[AVISO] Submetendo job para classificacao com GTDBTK para fila $I_FILA_CLUSTER com nome $I_NOME_JOB" >> "$LOG_FILE"
    
    I_LISTA_VAR=(
    "LOG_FILE=$LOG_FILE"
    "OUTPUT_DIR=$OUTPUT_DIR"
    "H_LISTA_GENOMAS_NAO_CLASSIFICADOS=$H_LISTA_GENOMAS_NAO_CLASSIFICADOS"
    "F_EXTENSAO_ARQUIVO_GENOMA=$F_EXTENSAO_ARQUIVO_GENOMA"
    "I_NUMERO_CPUS=$I_NUMERO_CPUS"
    "I_NUMERO_CPUS_PPLACER=$I_NUMERO_CPUS_PPLACER"
    "I_DIR_OUTPUT_RESULTADOS_GTDBTK=$I_DIR_OUTPUT_RESULTADOS_GTDBTK"
    "H_OUTPUT_TAXONOMIA=$H_OUTPUT_TAXONOMIA"
    "I_OUTPUT_TAXONOMIA_COMPLETA=$I_OUTPUT_TAXONOMIA_COMPLETA"
    )

    # IFS (Defini o separador interno entre os elementos de um array)
    IFS=,
    qsub \
        -N "$I_NOME_JOB" \
        -q "$I_FILA_CLUSTER" \
        -l "nodes=1:ppn=$I_NUMERO_CPUS,mem=${I_MEMORIA_RAM}gb,walltime=$I_WALLTIME_MAX" \
        -v "${I_LISTA_VAR[*]}" \
        "$I_NOME_PBS" >> "$LOG_FILE" 2>&1 \
        || { echo "Nao foi possivel submeter o job $I_NOME_JOB com qsub" >> "$LOG_FILE" ; exit 1 ; }
    unset IFS
fi
    
    # 9) Resultados
    # arquivo_existe_no_output "$I_OUTPUT_TAXONOMIA_COMPLETA"
    
    ##### COMO CONTINUAR A EXECUCAO DESSE SCRIPT?? CONSIDERANDO QUE SO PODE COMECAR QUANDO O OUTRO ARQUIVO TERMINAR ????? ###3
    
    # 10) Criacao de uma estrutura de diretorios a partir da classificao taxonomica
    J_ESTRUTURA_DIR="TAXONOMY-DIRECTORY-STRUCTURE-${TAXON_ANALISADO}"

    # 10.1) Verificando argumento

    # 10.2) Imprimindo o bloco de execucao no log
    cat << EOF >> "$LOG_FILE"

======== 10) CRIANDO ESTRUTURA DE DIRETORIOS COM A TAXONOMIA ========

Arquivos gerados
Estrutura de diretorios para taxonomia: $J_ESTRUTURA_DIR

EOF

    # 10.3) Chamando a funcao
    # Uso: create_taxonomic_dir_structure <taxonomy_file> <taxonomic_dir_name> <dir_genomas> <extensao_genoma>
    
    if [[ "$H_NUM_GENOMAS_NAO_CLASSIFICADOS" -gt 0 ]]; then
        create_taxonomic_dir_structure "$I_OUTPUT_TAXONOMIA_COMPLETA" "$J_ESTRUTURA_DIR" "$A_DIR_GENOMAS" "$F_EXTENSAO_ARQUIVO_GENOMA"  || return 1
    else
        create_taxonomic_dir_structure "$H_OUTPUT_TAXONOMIA" "$J_ESTRUTURA_DIR" "$A_DIR_GENOMAS" "$F_EXTENSAO_ARQUIVO_GENOMA"  || return 1
    fi


    # 11) - Desreplicar os genomas do dir-tax com skDER (ou CIDDER)
    K_DIR_TAXONOMICO_REPRESENTATIVO="REPRESENTATIVE-${NOME_BASE}"
    K_OUTPUT_METADADOS_DESREPLICADOS="REPRESENTATIVE-METADATA-${NOME_BASE}.tsv"
    K_PROGRAMA_FILTRAGEM_MGE="phispy" # genomad ou phispy (default: phispy)
    K_LISTA_DIR_ESPECIES_COM_1_GENOMA="lista_dir_especies_com_1_genoma.txt"
    K_LISTA_GENOMAS_REPRESENTATIVOS="lista_genomas_representativos.txt"
    
    
    # 11.1) Verificando argumento

    # 11.2) Imprimindo o bloco de execucao no log
    cat << EOF >> "$LOG_FILE"

======== 11) IDENTIFICANDO GENOMAS REPRESENTATIVOS COM SKDER ========

Parametros selecionados
Programa para filtragem de MGE: $K_PROGRAMA_FILTRAGEM_MGE

Arquivos gerados
Estrutura de diretorios de genomas representativo: $K_DIR_TAXONOMICO_REPRESENTATIVO
Metadados dos genomas representativos: $K_OUTPUT_METADADOS_DESREPLICADOS
Lista de genomas com apenas 1 representante na especie: $K_LISTA_DIR_ESPECIES_COM_1_GENOMA
Lista de genomas representativos: $K_LISTA_GENOMAS_REPRESENTATIVOS

EOF


    # 11.3) Chamando a funcao
    
    # Uso: desreplicacao_no_dir_taxonomia <estrutura_dir_taxonomia> <max_memoria> <num_cpus> <dir_output_gen_representativos> <lista_genomas_unicos> <programa_filtrar_mge>
    desreplicacao_no_dir_taxonomia "$J_ESTRUTURA_DIR" "$MEMORIA_RAM" "$NUMERO_CPU" "$K_DIR_TAXONOMICO_REPRESENTATIVO" "$K_LISTA_DIR_ESPECIES_COM_1_GENOMA" "$K_PROGRAMA_FILTRAGEM_MGE"  || return 1

    # Uso: selecionar_metadados_de_representativos <dir_tax_genomas_rep> <metadados_genomas_nao_desreplicados> <output_met_desreplicados> <extensao_genoma> <lista_dir_genomas_unicos> <lista_genomas_rep>
    selecionar_metadados_de_representativos "$K_DIR_TAXONOMICO_REPRESENTATIVO" "$G_OUTPUT_METADADOS_ALTA_QUALIDADE" "$K_OUTPUT_METADADOS_DESREPLICADOS" "$F_EXTENSAO_ARQUIVO_GENOMA" "$K_LISTA_GENOMAS_UNICOS" "$K_LISTA_GENOMAS_REPRESENTATIVOS" || return 1
    
    # 13) Gerar graficos com os arquivos gerados

    # 13.2) Imprimindo o bloco de execucao no log
    cat << EOF >> "$LOG_FILE"

======== 13) GERANDO GRAFICOS ========

Graficos gerados
BARRA V - Numero total de genomas baixados em relacao ao numero de classificados como $D_CATEGORIA
BARRA V - Numero total de genomas classificados como $D_CATEGORIA
UPSET - Origem da classificao do genoma como $D_CATEGORIA
VIOLINO - Distribuicao da qualidade dos genomas de acordo com CheckM2 (versao $(checkm2 --version))
BARRA H - Numero de genomas classificados pelo GTDB e nao classificados
BARRA H - Numero de taxons diferentes (especie, genero, familia, ..., dominio)
BARRA H - Taxons mais representativos (taxons com maior numero de genoma - um para cada nivel)
DISTRIBUICAO - Numero de genomas por especie

EOF

# ta é o seguinte, eu preciso da sua ajudar para fazer uma tarefa grande:

# Preciso escrever um script R para fazer o plot de todos esses graficos (v - vertical e h - horizontal)

# BARRA V - Numero total de genomas baixados em relacao ao numero de classificados como $D_CATEGORIA
# BARRA V - Numero total de genomas classificados como $D_CATEGORIA
# UPSET - Origem da classificao do genoma como $D_CATEGORIA
# VIOLINO - Distribuicao da qualidade dos genomas de acordo com CheckM2 (versao $(checkm2 --version))
# BARRA H - Numero de genomas classificados pelo GTDB e nao classificados
# BARRA H - Numero de taxons diferentes (especie, genero, familia, ..., dominio)
# BARRA H - Taxons mais representativos (taxons com maior numero de genoma - um para cada nivel)
# DISTRIBUICAO - Numero de genomas por especie

# vc pode escolher se achar melhor escrever o script para plot em R de todos esses graficos juntos ou separados, mas a questao é que eu quero q vc construa esses graficos levando em considerando o input de cada um que irei listar abaixo:
# 1) BARRA V - Numero total de genomas baixados em relacao ao numero de classificados como $D_CATEGORIA
# INPUT: Arquivo tsv com HEADER. Possui 

echo -ne "\n============= FIM DO SCRIPT ===============\n" >> "$LOG_FILE"
exit 0

}
    


# Funcoes auxiliares
echo_erro () {
    local MENSAGEM="${@?}"
    local DATA="$(date +"%H:%M:%S")"
    echo "[${DATA}] ERRO: $MENSAGEM" >&2
}

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

contar_genomas () {
    local ARQ_GENOMAS="${1?}"
    local HEADER="true"
    case "$2" in
        -n|--no_header)
            local HEADER="false"
            ;;
        *)
            if [[ ! -z "$2" ]]; then
                echo "[ERRO] Flag invalida $2"
                return 1
            fi
    esac
    
    [ -f "$ARQ_GENOMAS" ] || { echo "[ERRO] Nao foi possivel encontrar $ARQ_GENOMAS em $(pwd)" >> "$LOG_FILE" ; return 1 ; }
    if [[ "$HEADER" == "true" ]]; then
        local TOTAL_GENOMAS="$(tail -n +2 $ARQ_GENOMAS | wc -l)"
    else
        local TOTAL_GENOMAS="$(wc -l < "$ARQ_GENOMAS")"
    fi
    echo "$TOTAL_GENOMAS"
}

# Salvar andamento da execucao dentro de um arquivo de checkpoint

save_step () {
    [ -f "$CHECKPOINT_FILE" ] || { echo "[ERRO] Nao foi possivel salvar etapa $1: Arquivo de checkpoint $CHECKPOINT_FILE nao encontrado" ; return 1 ; }
    echo "$1" >> "$CHECKPOINT_FILE" 
}

get_last_step () {
    if [[ ! -f "$CHECKPOINT_FILE" ]]; then
        echo "Nao foi possivel recuperar ultima etapa: Arquivo de checkpoint $CHECKPOINT_FILE nao encontrado em $OUTPUT_DIR"
        echo "Criando novo arquivo $CHECKPOINT_FILE"
        echo "1" > "$CHECKPOINT_FILE"
    fi
    echo "$(tail -n1 "$CHECKPOINT_FILE")"
}




# # 12) - Associando informacoes aos metadados - MAGs, Dados de cultivo, Temperatura de Crescimento
# DIR_TAXONOMICO_DESREPLICADO="NONREDUNDANT-${NOME_BASE}"
# OUTPUT_METADADOS_DESREPLICADOS="NONREDUNDANT-${NOME_BASE}.tsv"

# # 10.1) Verificando argumento

# # 10.2) Imprimindo o bloco de execucao no log

# # 10.3) Chamando a funcao

# # Uso da funcao 

# # ETAPA DE VERIFICACAO - verificar se todos os arquivos/diretorios necessarios para execucao existem e verificar se todos os modulos (funcoes) estao presente

# DIR_MODULOS="Functions"
# MODULOS_EXECUCAO=( 
# "A_Download-Dehydrated-Genomes.sh"
# "B_Get-Metadata-Dehydrated-Genomes.sh"
# "C_Filter-Raw-Metadata.sh"
# "D_Categorize-Metadata-By-Group.sh"
# "E_Rehydrate-Selected-Genomes.sh"
# "6_Calculate-Quality-Score.sh"
# "7_Select-High-Quality-Genomes.sh"
# "8_Create-Taxonomy-Classification-File.sh"
# "9_Find-Missing-Taxonomy.sh"
# "10_Create-Taxonomy-Directory-Structure.sh"
# "11_Desreplicate-Curated-Genomes.sh"
# )



















# # # VARIAVEIS - 11) Adicionar metadados adicionais (dados de cultivo, mags, ...)
# # TERMOS_PARA_IDENTIFICACAO_MAGS="" # MAG, metagenome
# # DADOS_CULTIVO=""

# # VARIAVEIS - 12) Gerar graficos dos dados com R
# SCRIPT_R=""

# # grafico - numero de genomas, identificao termofilos (UpSet), distribuicao da qualidade (Violino+Nuvem de pontos), distribuicao taxonomica, numero genomas no GTDB, distribuicao das cepas termofilicas+temperatura de crescimento (dados de cultivo), distribuicao ambiental (fonte de isolamento, nicho ecologico), distribuicao no mundo (usando geolocalizacao - longitude e latitude)

# # OUTRAS VARIAVEIS - versoes das ferramentas
# VERSAO_DATASETS="$(datasets --version)"
# VERSAO_TAXONKIT="$(taxonkit --version)" # para usar APENAS as classicacoes taxonomicas do GTDB, passo o dump file gtdb-taxdump
# # OPCAO - Usar o programa gtdb_to_taxdump para fazer a conversao da base de dados do gtdb para o formato tax_dump do NCBI e passar para o taxonkit
# # https://github.com/nick-youngblut/gtdb_to_taxdump
# VERSAO_CHECKM2="$(checkm2 --version)"
# VERSAO_GTDB-TK="$(gtdb-tk --version)"


# # DOWNLOAD DOS GENOMAS DESIDRATADOS (apenas metadados sao baixados)
# echo "Submetendo job para download dos genomas desidratados"

# ANOS=("antes_2017" 2018 2019 2020 2021 2022 2023 2024 2025 2026)
# ANO_INICIAL="${ANOS[0]}"
# ANO_FINAL="${ANOS[-1]}"
# INTERVALO_ANOS="${ANO_INICIAL}-${ANO_FINAL}"
# # Transforma o array em uma string de elementos separados por espaço para o job filho
# ANOS_STRING="${ANOS[*]}"
    
# NOME_SCRIPT="genoma-bacteria_${INTERVALO_ANOS}.sh"
# NOME_JOB="download_${INTERVALO_ANOS}"
    
    # cat << EOF > "$NOME_SCRIPT"
# #!/usr/bin/env bash
# #PBS -N $NOME_JOB
# #PBS -l nodes=1:ppn=4,mem=4gb,walltime=72:00:00
# #PBS -q qtime
# #PBS -v NCBI_API_KEY

# # Preparacao do PBS
# cd "\${PBS_O_WORKDIR}" || exit
# source "/etc/profile.d/modules.sh"

# # Chamada dos modulos (sem barras nos comandos)
# module load ncbi_datasets/18.26.0 

# # Importacao da funcao
# source "Functions/Download-Genoma-Desidratados.sh"

# # Executa passando a string de anos gerada pelo Pai
# download_bacteria_genomes_by_years $ANOS_STRING

# EOF

# # 1 - Submeter o job de download dos genomas e metadados desidratados
# ID_COMPLETO=$(qsub "$NOME_SCRIPT")
# JOB_ID=$(echo "$ID_COMPLETO" | cut -d'.' -f1)
    
# if [ -z "$IDS_FILHOS" ]; then
    # IDS_FILHOS="$JOB_ID"
# else
    # IDS_FILHOS="${IDS_FILHOS}:${JOB_ID}"
# fi

# # Cria o script de junção para concatenar os metadados de cada ano
# echo "Submetendo o job de concatenação dos metadados dos genomas baixados e fetch.txt"

# cat << EOF > unir_genomas_bacteria.sh
# #!/usr/bin/env bash
# #PBS -N Merge_Genomes
# #PBS -l nodes=1:ppn=4,mem=4gb,walltime=72:00:00
# #PBS -q qtime
# #PBS -v NCBI_API_KEY

# # Preparacao do PBS
# cd "\${PBS_O_WORKDIR}" || exit
# source "/etc/profile.d/modules.sh"

# module load ncbi_datasets/18.26.0 

# source "Functions/Converter-Metadados-Desidratados.sh"

# # Cria um novo arquivo para guardar os metadados
# > complete_bacteria_metadata.tsv

# if [[ -d ncbi_genomes_bacteria-$INTERVALO_ANOS ]]; then
    # echo "Diretorio contendo os genomas encontrado"
# else
    # echo "ERRO - diretorio contendo os genomas nao encontrado"
    # echo "Fim do job de concatenacao"
    # return 1
# fi

# FIRST_DIR=true

# # Loop para concatenar os metadados e fetch.txt de cada ano
# for dir in ncbi_genomes_bacteria-$INTERVALO_ANOS/*/; do
    # dir_limpo="\${dir%/}"  # Remove a barra do final
    # nome_pasta=\$(basename "\${dir_limpo}") # Pega só o nome final da pasta
    
    # TEMP_OUTPUT="bacteria_metadata-\${nome_pasta}.tsv"
    
    # # Chama a funcao passando o diretorio desidratado com os metadados + fetch.txt e o nome do output
    # convert_dehydrate_metadata_to_tsv "\${dir}" "\${TEMP_OUTPUT}"
    
    # # Cria arquivo novo ou concatena no arquivo ja criado os metadados
    # if [ "\${FIRST_DIR}" = true ]; then
        # cat "\${TEMP_OUTPUT}" > complete_bacteria_metadata.tsv
        # FIRST_DIR=false
    # else
        # tail -n +2 "\${TEMP_OUTPUT}" >> complete_bacteria_metadata.tsv
    # fi
    
    # # Remove o tsv temporario do ano apos concatenar
    # rm "\${TEMP_OUTPUT}"
# done

# # Remover os outros jobs q foram utilizados
# rm "genoma-bacteria_\${INTERVALO_ANOS}.sh"

# EOF

# # 2 - Submete o job de concatenação com a dependência no job de download (JOB1) # funcao ja faz a criacao de um arquivo com 'todos' os metadados"
# # falto concatenar os fetch.txt
# qsub -W depend=afterok:${IDS_FILHOS} unir_genomas_bacteria.sh

# 3 - Submeter o job de filtragem dos metadados incompleto e completo (depende do JOB2) ## retirar GCF, se tiver, colocar NULL nos campos vazios
# 4 - Submeter o job de identificar termofilos (depende do JOB3) ## funcao ja faz a identificao e cria um novo arquivo so com termofilos
# 5 - Submeter o job de selecao, pelo fetch.txt, e hidratacao dos genomas de termofilos (depende do JOB4)
# 5.1 - Submeter o job de identificao de cepas termofilicas e adicao de dados de cultivo (depende de JOB4)
# 6 - Submeter o job de calculo da qualidade e filtragem dos genomas de termofilos, utilizando o CheckM2 (depende do JOB5)
# 7 - Submeter o job de busca por classificao taxonomica dos genoma curados de termofilos no GTDB (depende do JOB6)
# 8 - Submeter o job de classificacao taxonomica com GTDB-Tk (depende do JOB7) # Vou buscar a classificacao apenas dos genomas q nao estiverem no GTDB
# 9 - Submeter o job de criacao da estrutura de diretorios taxonomicos (depende do JOB 8)
# 10 - Desreplicar os genomas que estiverem na mesma pasta da estrutura taxonomica, tem mesma cepa ou mesma classificao tax (depende do JOB9)
# 11 - Submeter o job de gerar graficos (depende JOB9) # grafico - numero de genomas, identificao termofilos (UpSet), distribuicao da qualidade (Violino+Nuvem de pontos), distribuicao taxonomica, numero genomas no GTDB, distribuicao das cepas termofilicas+temperatura de crescimento (dados de cultivo), distribuicao ambiental (fonte de isolamento, nicho ecologico), distribuicao no mundo (usando geolocalizacao - longitude e latitude)
# 12 - Remover todos os arquivos dos jobs criados e organizar arquivos para as devidas pastas

############ LEMBRAR DE TRANSFERIR AS VENV PARA OS JOBS FILHOS - #PBS -v <var_ambiente> #############
# JOB PAI conhece as variaveis do meu ~/.bashrc, mas os FILHOS nao

# # Carregando os modulos necessarios (SEMPRE CARREGAR NA MESMA LINHA - evitar overwriting)
# module load ncbi_datasets/18.26.0 taxonkit

# # Configura variaveis de ambiente para o datasets e taxonkit, respectivamente
# export NCBI_API_KEY="eaf5670789ddab3396e42e74829340903907"
# export TAXONKIT_DB_DIR="/data/db/taxonkit/0.20.0/19052026"


# Chamar scripts com as funcoes necessarias
# source "Functions/Download_Metadata_NCBI.sh"
# source "Functions/Filter_Data_NCBI.sh"
# source "Functions/Find_Thermophile_NCBI.sh"
# source "Functions/Create_Taxonomic_Classification.sh"
# source "Functions/Create_Taxonomic_Directory.sh"

# download_metadata_ncbi "bacteria_metadata.tsv" "2" "break_request"
# download_metadata_ncbi "archaea_metadata.tsv" "2157" "simple_request"

# filter_metadata "bacteria_metadata.tsv" "FILTERED_bacteria_metadata.tsv"
# filter_metadata "archaea_metadata.tsv" "FILTERED_archaea_metadata.tsv"

# find_thermophile "FILTERED_bacteria_metadata.tsv" "thermophilic_bacteria_metadata.tsv"
# find_thermophile "FILTERED_archaea_metadata.tsv" "thermophilic_archaea_metadata.tsv"

# awk -F'\t' '$6 ~ /THERMOPHILIC/ || $7 ~ /THERMOPHILIC/' "thermophilic_bacteria_metadata.tsv" > "only-thermophilic_bacteria_metadata.tsv"
# awk -F'\t' '$6 ~ /THERMOPHILIC/ || $7 ~ /THERMOPHILIC/' "thermophilic_archaea_metadata.tsv" > "only-thermophilic_archaea_metadata.tsv"

# create_taxonomy_file "only-thermophilic_bacteria_metadata.tsv" "thermophilic_bacteria_taxonomy.tsv"
# create_taxonomy_file "only-thermophilic_archaea_metadata.tsv" "thermophilic_archaea_taxonomy.tsv"

# create_taxonomy_dir_structure "thermophilic_bacteria_taxonomy.tsv" "Bacteria-TaxonomicStructure"
# create_taxonomy_dir_structure "thermophilic_archaea_taxonomy.tsv" "Archaea-TaxonomicStructure"

# download_genome_ncbi "only-thermophilic_bacteria_metadata.tsv" "thermophilic_bacteria_taxonomy.tsv" "Bacteria-TaxonomicStructure" "ncbi_genomes_bacteria"
# download_genome_ncbi "only-thermophilic_archaea_metadata.tsv" "thermophilic_archaea_taxonomy.tsv" "Archaea-TaxonomicStructure" "ncbi_genomes_archeae"

# create_complete_ncbi_metadata_file "METADATA-ncbi_genomes_bacteria/ncbi_dataset/data/assembly_data_report.jsonl" "thermophilic_bacteria_complete_metadata.tsv"
# create_complete_ncbi_metadata_file "METADATA-ncbi_genomes_archaea/ncbi_dataset/data/assembly_data_report.jsonl" "thermophilic_archaea_complete_metadata.tsv"

# create_additional_metadata_file "only-thermophilic_bacteria_metadata.tsv" "ADDITIONAL-thermophilic_bacteria_metadata.tsv"
# create_additional_metadata_file "only-thermophilic_archaea_metadata.tsv" "ADDITIONAL-thermophilic_bacteria_metadata.tsv"

##### JA FIZERAM O QUE EU QUERO FAZER - https://github.com/pirovc/genome_updater
# A ferramenta ja existe é um Genome Updater, que faz o download de genomas do NCBI e faz uma filtragem para manter apenas os nao redundantes
# PRECISO ESPECIALIZAR MINHA FERRAMENTA - Foco na identificao de grupos especificos (como por fonte de isolamento) - foco em EXTREMOFILOS
# Ferramenta do cara é uma ferramenta com multi-parametros e que dá diversas opcoes para deixar o programa altamente customizavel
# Mas a alta customizacao tem custo, necessita de muito codigo e verificao. Talvez o meu script poderia ser mais focado em uma tarefa especifica,
# sem tanta customizacao
# Meu script tbm ja gera graficos :)

###### GENOME UPDATER FOR PROKARYOTIC GENOMAS - Exemplo 