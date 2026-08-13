# Funcao para selecionar os genomas da categoria de interesse do fetch.txt e reidrata-los (baixar arquivo FASTA)

# Chamada das funcoes:
# Uso: update_genomes_url_file <fetch.txt original> <metadados_categorizados> <fetch.txt categoria> <categoria>
# rehydrate_selected_genomes <dir_genomas> <numero_conexoes> <download_gzip:true:false> <dir_fasta_genomas>

update_genomes_url_file () {
    local CAMINHO_ARQUIVO_URL="${1?}" # fetch.txt original
    local ARQUIVO_METADADOS_CATEGORIZADOS="${2?}"
    local OUTPUT_URL_CATEGORIA="${3?}" # fetch.txt modificado
    local CATEGORIA="${4?}"
    
    # Criando arquivo de saida
    > "$OUTPUT_URL_CATEGORIA" && echo "Criando arquivo $OUTPUT_URL_CATEGORIA para recuperacao dos genomas da categoria em $OUTPUT_DIR" >> "$LOG_FILE"
    
    # O awk agora roda solto, sem atribuição de variável gritante
    awk -v category="$CATEGORIA" \
        -v out_genomas="$OUTPUT_URL_CATEGORIA" \
        -v log_file="$LOG_FILE" '
        
        # 1. Indexa as linhas de URL do fetch.txt na memória (primeiro arquivo - enquanto NR for igual ao FNR)
        NR == FNR {
            if (match($0, /GC[AF]_[0-9]+\.[0-9]+/)) {
                acesso_fetch = substr($0, RSTART, RLENGTH) 
                fetch[acesso_fetch] = $0
            }
            next;
        }
        
        # 2. Busca pelo codigo de acesso do genoma dos metadados (1° coluna) no hash map do fetch 
        FNR > 1 { # pula o header
            if ($1 in fetch) {
                # Escreve arquivo de saída
                print fetch[$1] >> out_genomas; 
                contador++;
            }
        }
        
        # 3. Bloco final executado após ler os dois arquivos
        END {
            mensagem = "[INFO] Criado novo arquivo com URL para download de " (contador + 0) " genomas " category;
            print mensagem >> log_file;
        }
    ' "$CAMINHO_ARQUIVO_URL" "$ARQUIVO_METADADOS_CATEGORIZADOS" || { echo "[ERRO] Comando awk para selecao de url falhou" >> "$LOG_FILE" ; return 1 ; }

    # Trocando o fetch.txt original de nome
    mv "$CAMINHO_ARQUIVO_URL" "${CAMINHO_ARQUIVO_URL%.*}-original.txt" || { echo "[ERRO] Ao mover $CAMINHO_ARQUIVO_URL para ${CAMINHO_ARQUIVO_URL%.*}-original.txt" >> "$LOG_FILE" ; return 1 ; }
    
    # Colocando o arquivo atualizado como novo fetch.txt
    mv "$OUTPUT_URL_CATEGORIA" "$CAMINHO_ARQUIVO_URL" || { echo "[ERRO] Ao mover $OUTPUT_URL_CATEGORIA para $CAMINHO_ARQUIVO_URL" >> "$LOG_FILE" ; return 1 ; }
    
}

rehydrate_selected_genomes () {
    local DIR_GENOMAS="${1?}" # pasta deve conter o fetch.txt atualizado
    local NUMERO_CONEXOES_SIMULTANEAS="${2?}" # default - 10 (range: 1-30)
	local DOWNLOAD_ARQUIVOS_COMPACTADOS="${3?}" # true ou false
	local PASTA_GENOMAS="${4?}"
    
    # Monta a flag do gzip se for true
    local FLAG_GZIP=""
    local EXTENSAO_GENOMA="fna"
	if [[ "$DOWNLOAD_ARQUIVOS_COMPACTADOS" == "true" ]]; then
		FLAG_GZIP="--gzip"
        EXTENSAO_GENOMA="gz"
	fi
    
    # Executa repetidamente até que o comando retorne código 0 (sucesso)
    echo "[INFO] Iniciando a hidratação no diretório: $DIR_GENOMAS" >> "$LOG_FILE"
    until datasets rehydrate $FLAG_GZIP --max-workers "$NUMERO_CONEXOES_SIMULTANEAS" --directory "$DIR_GENOMAS"; do
        echo "[AVISO] O datasets falhou ou foi interrompido. Reiniciando download..." >> "$LOG_FILE"
        sleep 2
    done

    # Encontrar os genomas e mover todos os genomas para uma unica pasta (DIR_GENOMAS/ncbi_dataset/data/)
    find "${PASTA_GENOMAS}"/GC[AF]_*/ -type f -name "*.${EXTENSAO_GENOMA}" -exec mv -t "${PASTA_GENOMAS}" {} + \
    || { echo "[ERRO] Nao foi possivel unir os genomas em $PASTA_GENOMAS" >> "$LOG_FILE" ; return 1 ; }
    
    # Remover as pastas vazias 
    rm -d "${PASTA_GENOMAS}"/GC[AF]_*/ \
    || { echo "[ERRO] Nao foi possivel remover as pastas de genomas" >> "$LOG_FILE" ; return 1 ; }
    
    echo "[SUCESSO] Todos os genomas hidratados foram colocados na pasta para $PASTA_GENOMAS" >> "$LOG_FILE"
}