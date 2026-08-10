###### FUNCOES AUXILIARES ##########

# Funcao para atualizar as tabelas de metadados a medida que novos genomas forem filtrados
# e transferir os metadados removidos para uma nova tabela 

# Uso: atualizar_tabelas_metadados <lista_genomas:coluna unica:sem HEADER:caminho/acesso do genoma> <dir_metadados_selecionados> 
# <dir_metadados_removidos> <dir_metadados_originais:OPCIONAL>
atualizar_tabelas_metadados () { 
    local LISTA_GENOMAS="${1?}"
    local DIR_METADADOS_SELECIONADOS="${2?}"
    local DIR_METADADOS_INDESEJADOS="${3?}"
    local DIR_METADADOS_ORIGINAIS="$4"
    
    # 0. Caso seja a primeira execucao, guardar os metadados no dir de metadados originais
    # Testa se a variavel foi informada E se o diretorio ainda nao existe
    if [[ -n "$DIR_METADADOS_ORIGINAIS" && ! -d "$DIR_METADADOS_ORIGINAIS" ]]; then
        mkdir -p "$DIR_METADADOS_ORIGINAIS" \
            || { echo "[ERRO] Nao foi possivel gerar diretorio $DIR_METADADOS_ORIGINAIS" >> "$LOG_FILE" ; return 1 ; }
            
        # O asterisco fica fora das aspas para o Bash expandir os arquivos
        cp "$DIR_METADADOS_SELECIONADOS"/*.tsv "$DIR_METADADOS_ORIGINAIS" \
            || { echo "[ERRO] Nao foi possivel copiar metadados para diretorio $DIR_METADADOS_ORIGINAIS" >> "$LOG_FILE" ; return 1 ; }
    fi
	if [[ ! -f "$LISTA_GENOMAS" || -d "$LISTA_GENOMAS" || ! -s "$LISTA_GENOMAS" ]]; then
		echo "[ERRO] Lista de genomas '$LISTA_GENOMAS' invalida" >> "$LOG_FILE"
		return 1
	fi
	
    # 1. Extraindo apenas os accession IDs válidos e ignorando linhas vazias/NULL
    local LISTA_ID_GENOMAS
    LISTA_ID_GENOMAS=$(mktemp)
    awk -F'\t' '
    {
        if (match($0, /GC[AF]_[0-9]+\.[0-9]+/)) {
            print substr($0, RSTART, RLENGTH)
        }
    }' "$LISTA_GENOMAS" > "$LISTA_ID_GENOMAS"
    # Se a lista de IDs estiver vazia, não há o que filtrar
    if [[ ! -s "$LISTA_ID_GENOMAS" ]]; then
        echo "[ERRO] Nenhum ID de genoma valido encontrado em: ${LISTA_GENOMAS}" >> "$LOG_FILE"
        rm -f "$LISTA_ID_GENOMAS"
        return 1
    fi

    # 2. Loop pelas 4 tabelas de metadados
	local num_tabelas_metadados="${#VETOR_CAMPOS[@]}"
	if [[ "$num_tabelas_metadados" == 0 || -z "$num_tabelas_metadados" ]]; then
		echo "[ERRO] Vetor com os metadados $VETOR_CAMPOS nao encontrado!" >> "$LOG_FILE"
		return 1
	fi
    for ((i=0; i<"$num_tabelas_metadados"; i++)); do
        local ARQUIVO_METADADOS="${DIR_METADADOS_SELECIONADOS}/${VETOR_OUTPUT_METADADOS[i]}"
        local ARQUIVO_INDESEJADOS="${DIR_METADADOS_INDESEJADOS}/${VETOR_OUTPUT_METADADOS[i]}"
        local NOME_CAMPO="${VETOR_NOMES_CAMPOS[i]}"
		
	# Verificar arquivos e diretorios
        if [[ ! -f "$ARQUIVO_METADADOS" ]]; then
            echo "[ERRO] Arquivo de metadados ${NOME_CAMPO} nao encontrado: ${ARQUIVO_METADADOS}" >> "$LOG_FILE"
            rm -f "$LISTA_ID_GENOMAS"
            return 1
        fi
		if [[ ! -d "$DIR_METADADOS_INDESEJADOS" ]]; then
			mkdir -p "$DIR_METADADOS_INDESEJADOS" \
				|| { echo "[ERRO] Nao foi possivel gerar diretorio $DIR_METADADOS_INDESEJADOS" >> "$LOG_FILE" ; return 1 ; }
		fi

        echo "[INFO] Atualizando metadados ${NOME_CAMPO}. Removendo genomas filtrados..." >> "$LOG_FILE"
        
        # Criar arquivos temporarios dedicados para ESTA iteracao do loop
        local METADADOS_TEMP_SELECIONADOS
        local METADADOS_TEMP_INDESEJADOS
        METADADOS_TEMP_SELECIONADOS=$(mktemp)
        METADADOS_TEMP_INDESEJADOS=$(mktemp)

        # 3.1. Isolando genomas selecionados (mantem o cabecalho)
        head -n 1 "$ARQUIVO_METADADOS" > "$METADADOS_TEMP_SELECIONADOS"
        tail -n +2 "$ARQUIVO_METADADOS" | grep -F -f "$LISTA_ID_GENOMAS" >> "$METADADOS_TEMP_SELECIONADOS" || true
        
        # 3.2. Isolando genomas indesejados (mantem o cabecalho), ou concatenando caso ja haja o arquivo
        if [ ! -f "$ARQUIVO_INDESEJADOS" ]; then 
            head -n 1 "$ARQUIVO_METADADOS" > "$METADADOS_TEMP_INDESEJADOS"
            tail -n +2 "$ARQUIVO_METADADOS" | grep -v -F -f "$LISTA_ID_GENOMAS" >> "$METADADOS_TEMP_INDESEJADOS" || true
            mv "$METADADOS_TEMP_INDESEJADOS" "$ARQUIVO_INDESEJADOS"
        else 
            tail -n +2 "$ARQUIVO_METADADOS" | grep -v -F -f "$LISTA_ID_GENOMAS" >> "$ARQUIVO_INDESEJADOS" || true
            rm -f "$METADADOS_TEMP_INDESEJADOS"
        fi
            
        # 4. Sobrescreve o arquivo original com a versao filtrada
        mv "$METADADOS_TEMP_SELECIONADOS" "$ARQUIVO_METADADOS"
    done
    
    # 5. Remover arquivo temporario de IDs
    rm -f "$LISTA_ID_GENOMAS"
	
	echo "[INFO] Atualizacao dos metadados no diretorio $DIR_METADADOS_SELECIONADOS completa!" >> "$LOG_FILE"
}


# Funcao para atualizar o pasta com os FASTA dos genomas

# Uso: atualizar_pasta_genomas <lista_genomas> <pasta_genomas> <extensao_genoma>
atualizar_pasta_genomas () {
	local LISTA_GENOMAS="${1?}"
	local PASTA_GENOMAS="${2?}"
	local EXTENSAO_GENOMA="${3?}"
	local DIR_REMOVED="${4?}"
	
	# 0. Verificar se ha algum arquivo da extensao informada na pasta
	if ! ls "$PASTA_GENOMAS"/*."$EXTENSAO_GENOMA" 2>&1 > /dev/null; then
		echo "[ERRO] Nenhum genoma (.$EXTENSAO_GENOMA) encontrado no dir $PASTA_GENOMAS" >> "$LOG_FILE"
		return 1
	fi
	
	# 1. Extraindo apenas os accession IDs validos e ignorando linhas vazias/NULL
	local LISTA_ID_GENOMAS
	LISTA_ID_GENOMAS=$(mktemp)
	awk -F'\t' '
	{
		if (match($0, /GC[AF]_[0-9]+\.[0-9]+/)) {
			print substr($0, RSTART, RLENGTH)
		}
	}' "$LISTA_GENOMAS" > "$LISTA_ID_GENOMAS"
	# Se a lista de IDs estiver vazia, nao ha o que filtrar
	if [[ ! -s "$LISTA_ID_GENOMAS" ]]; then
		echo "[ERRO] Nenhum ID de genoma valido encontrado em: ${LISTA_GENOMAS}" >> "$LOG_FILE"
		rm -f "$LISTA_ID_GENOMAS"
		return 1
	fi
	
	# 2. Diretorio onde ficarao os genomas removidos
	if [[ ! -d "$DIR_REMOVED" ]]; then
		mkdir -p "$DIR_REMOVED" \
			|| { echo "[ERRO] Nao foi possivel criar o diretorio $DIR_REMOVED" >> "$LOG_FILE" ; return 1 ; }
	fi
	
	# 3. Filtrar com grep os arquivos que NAO estao na lista (-v)
	# find encontra os caminhos dos genomas
	# grep -v seleciona os genomas que NAO estao na lista
	# xargs organiza os arquivos da pipe para ter erro (Too many args)
	# mv -t move os genomas para o diretorio de removidos
	find "$PASTA_GENOMAS" -maxdepth 1 -name "*.$EXTENSAO_GENOMA" \
		| grep -v -F -f "$LISTA_ID_GENOMAS" \
		| xargs -r -d '\n' mv -t "$DIR_REMOVED"

	# Limpeza dos arquivos temporarios
	rm -f "$LISTA_ID_GENOMAS" "$ARQ_GENOMAS_REMOVER"
	
		echo "[INFO] Atualizacao dos genomas no diretorio $PASTA_GENOMAS completa!" >> "$LOG_FILE"
}