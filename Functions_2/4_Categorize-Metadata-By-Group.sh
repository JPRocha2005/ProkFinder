# Funcao para categorizar os metadados dos genomas de acordo com algum grupo (ex: termofilos), baseado em
# dados de cultivo, taxons da literatura e fontes de isolamento

# Chamada da funcao (nao deve-se expandir os vetores com $, deve-se passa-los completos)
# add_category_metadata <uncategorized_input> <diretorio_dados> <vetor_tabelas_dados> <vetor_nome_tabelas> <vetor_coluna_taxid> <isolation_source_file> <categoria> <output_categorizado> <output_apenas_categorizados>

add_category_metadata () {
    local UNCATEGORIZED_INPUT="${1?}"
    local DATA_DIR="${2?}"

    # declare -n faz a variável local apontar para o array global fornecido pelo nome
    declare -n VECTOR_DATA_TABLES="${3?}"
    declare -n VECTOR_NAME_TABLES="${4?}"
    declare -n VECTOR_TAXID_COLUMNS="${5?}"
    local VECTOR_SIZE="${#VECTOR_DATA_TABLES[@]}"

    local FILE_ISOLATION_SOURCE="${DATA_DIR}/${6?}"
    local CATEGORY="${7?}"
    local OUTPUT_CATEGORIZED="${8?}"
    local OUTPUT_ONLY_CATEGORIZED="${9?}"
    local LISTA_GENOMAS_DA_CATEGORIA="${10?}"


    # Verificando variaveis de ambiente - TAXONKIT
    if [[ "$TAXONKIT_DATA_DIR" == "" ]]; then
        echo "[ERROR] Variable TAXONKIT_DATA_DIR containing the path to the data used in taxonkit not founded!" >> "$LOG_FILE"
        return 1
    fi

    # Arquivos temporários para os taxid da literatura/cultivo e para o input modificado
    TEMP_INPUT=$(mktemp)
    declare -a VECTOR_TEMP_TAXID

    # Extraindo os TaxIDs das referência para o arquivo temporário
    for ((i=0; i<"$VECTOR_SIZE"; i++)); do
        echo "[INFO] Acessando tabela ${VECTOR_NAME_TABLES[i]}" >> "$LOG_FILE"
        TEMP_FILE=$(mktemp)
        VECTOR_TEMP_TAXID+=("$TEMP_FILE")
        # CORRIGIDO: Chaves adicionadas em ${VECTOR_TEMP_TAXID[i]}
        tail -n +2 "${DATA_DIR}/${VECTOR_DATA_TABLES[i]}" | cut -f"${VECTOR_TAXID_COLUMNS[i]}" >> "${VECTOR_TEMP_TAXID[i]}"

        # Ordena, remove duplicados e linhas em branco do arquivo temp com os taxid
        sort -u "${VECTOR_TEMP_TAXID[i]}" | grep -v '^$' > "${VECTOR_TEMP_TAXID[i]}.clean"
        mv "${VECTOR_TEMP_TAXID[i]}.clean" "${VECTOR_TEMP_TAXID[i]}"
    done

    # Inserindo HEADER no output
    echo -en "$(head -n1 "$UNCATEGORIZED_INPUT")\tGenus_TaxID\tSpecies_TaxID\tClassification-Isolation-Source\tIsolation-Source-${CATEGORY}-Keyword\t" > "$OUTPUT_CATEGORIZED"
    for ((i=0; i<"$VECTOR_SIZE"; i++)); do
        echo -en "Classification-${VECTOR_NAME_TABLES[i]}\t" >> "$OUTPUT_CATEGORIZED"
    done
    echo -en "Classification-General\n" >> "$OUTPUT_CATEGORIZED" # Classificao geral

    # Buscando o taxid da especie/genero dos genomas no arquivo UNCATEGORIZED_INPUT a partir do taxid do organismo
    tail -n +2 "$UNCATEGORIZED_INPUT" | \
    taxonkit reformat2 \
    --data-dir "${TAXONKIT_DATA_DIR}" \
    -I 2 -t -f "{genus}\t{species}" \
    -r "NULL" -R "NULL" | \
    rev | cut -f1,2,5- | rev > "$TEMP_INPUT"

    # Colunas do TEMP_INPUT
    # Taxid-Genero = penultima coluna (NF-1) / Taxid-Especie = ultima coluna (NF)

    # Colocando as categorias no arquivo - TAXID e Fonte de Isolamento
    awk -F'\t' -v OFS='\t' \
    -v VECTOR_SIZE="$VECTOR_SIZE" \
    -v CATEGORY="$CATEGORY" '
        # Arquivos do vetor - TAXID ---
        ARGIND <= VECTOR_SIZE {
            db_taxid[ARGIND, $1] = 1
            next
        }

        # Arquivo - Fonte de Isolamento
        ARGIND == (VECTOR_SIZE+1) {
            if ($0 != "") regex_isolamento[++count_isolamento] = $0
            next
        }

        # Arquivo - TEMP_INPUT
        ARGIND == (VECTOR_SIZE+2) {
            # NF-1 é Genero, NF é Especie 
            genus = $(NF-1)
            species = $NF
            
            # Teste 0: Classificacao generica (caso qualquer teste seguinte classifique como CATEGORY)
            general_class = "NULL"

            # Teste 1: TaxID - Literatura e Bancos de Dados
            for (db_taxid_ind = 1; db_taxid_ind <= VECTOR_SIZE; db_taxid_ind++) {
                class_db_taxid[db_taxid_ind] = "NULL"
                
                # Verificar se o taxid do genero ou especie do genoma esta em algum dos bancos de referencia (db_taxid)
                if ((genus != "NULL" && (db_taxid_ind, genus) in db_taxid) || (species != "NULL" && (db_taxid_ind, species) in db_taxid)) {
                    class_db_taxid[db_taxid_ind] = CATEGORY
                    general_class = CATEGORY
                }
            }

            # Teste 2: Fonte de Isolamento (Uso de padrao REGEX)
            class_isolation_source = "NULL"
            matched_keyword_IS = "NULL"
            if ($3 != "NULL" && $3 != "") {
                isolation_source_lower = tolower($3)
                for (i = 1; i <= count_isolamento; i++) {
                    if (isolation_source_lower ~ regex_isolamento[i]) {
                        class_isolation_source = CATEGORY
                        general_class = CATEGORY
                        matched_keyword_IS = regex_isolamento[i]
                        break
                    }
                }
            }
            
            

            # Escrita dos dados processados
            
            # Escrita da classificacao pela fonte de isolamento
            printf "%s%s%s%s%s", $0, OFS, class_isolation_source, OFS, matched_keyword_IS
            
            # Escrita da classicacao pelos bancos com taxid
            for (f = 1; f <= VECTOR_SIZE; f++) {
                printf "%s%s", OFS, class_db_taxid[f]
            }
            
            # Escrita da classificacao geral
            printf "%s%s", OFS, general_class
            printf "\n"
        }
    ' "${VECTOR_TEMP_TAXID[@]}" "$FILE_ISOLATION_SOURCE" "$TEMP_INPUT" >> "$OUTPUT_CATEGORIZED"

    # Gerar arquivo separado apenas com os genomas de termofilos
    awk -F'\t' -v CATEGORY="$CATEGORY" \
    -v lista_genomas_categoria="$LISTA_GENOMAS_DA_CATEGORIA" \
    -v output_metadados_categoria="$OUTPUT_ONLY_CATEGORIZED" '
        # Escreve o cabeçalho no novo arquivo
        NR == 1 { print $0 > output_metadados_categoria ; next }

        {
            # Busca da CATEGORIA em todas as colunas da linha
            for (i = 1; i <= NF; i++) {
                if ($i == CATEGORY) {
                    # Imprimi o acesso na lista
                    print $1 > lista_genomas_categoria
                    # Imprimi a linha inteira no arquivo de metadados
                    print $0 > output_metadados_categoria
                    next 
                }
            }
        }
    ' "$OUTPUT_CATEGORIZED"

    # Limpeza dos arquivos temporários do sistema
    rm -f "$TEMP_INPUT"
    for ((i=0; i<"$VECTOR_SIZE"; i++)); do
        rm -f "${VECTOR_TEMP_TAXID[i]}"
    done
    
    echo "Classificacao dos metadados da categoria $CATEGORY completa!" >> "$LOG_FILE"
}