# Funcoes para fazer o download de todos os genomas do $TAXON_ANALISADO na forma desidratada (apenas metadados)

# Chamada das funcoes:
# download_genomes_by_taxid <numero_taxid> <banco_dados> <output_dir_genomas>

checar_download_zip () {
    local ZIP_FILE="$1"

    # Se o arquivo não existir ou o teste falhar, retorna erro
    if [[ ! -f "$ZIP_FILE" ]]; then
        return 1
    fi

	# unzip (-q : quiet mode / -qq : quieter / -t : test mode)
    if unzip -qq -t "$ZIP_FILE" 2>/dev/null ; then
        return 0
    else
        return 1
    fi    
}

download_genomes_by_taxid () {
    local TAXID="${1?}"
    local BANCO_DADOS="${2?}"
	local DIR_OUTPUT="${3?}"
	
    local OUTPUT="${DIR_OUTPUT}.zip"
	local ANO_INICIAL="2017" # antes_2017
    local ULTIMO_ANO="$(date "+%Y")"
    local VETOR_ANOS=( $(seq -s' ' $ANO_INICIAL $ULTIMO_ANO) )
	
	# -- VERIFICANDO ARGUMENTOS ---
	if [[ -z "$NCBI_API_KEY" ]]; then
		echo "[WARNING] Variavel ambiente NCBI_API_KEY nao encontrada. Requisicao do server do NCBI pode ser mais lenta" >> "$LOG_FILE"
	fi
	
	# Download de TODOS genomas
	for ANO in "${VETOR_ANOS[@]}"; do
		local OUTPUT_ANO="${ANO}-${OUTPUT}"
		local DIR_OUTPUT_ANO="${ANO}-${DIR_OUTPUT}"

		# FLAGS - datasets download genome taxon:
		# --assembly-source: banco de dados de genomas de onde os genomas e seus metadados serao recuperados (GenBank - geral / RefSeq - genomas de referencia), default - GenBank
		# --exclude-atypical: exclui genomas/montagens atipicos
		# --dehydrate: nao baixa o FASTA completo dos genomas, mas traz um arquivo fetch.txt com a URL para recuperar esses genomas
		# --filename: nome do arquivo de saida (output) compactado onde estara os metadados e o fetch.txt
		# --released-before: dados que foram disponilizados na data ou antes (formato MM/DD/YYYY)
		# --released-after: dados que foram disponilizados na data ou antes (formato MM/DD/YYYY)
		
		
		# LOOP DE TENTATIVAS (Blindado contra quedas de conexão)
		while true; do
			if [ "$ANO" == "$ANO_INICIAL" ]; then
				echo "=> Baixando genomas lançadas ATÉ O FIM DE $ANO_INICIAL" >> "$LOG_FILE"
				FILTRO_DATA="--released-before 12/31/${ANO_INICIAL}"
			elif [ "$ANO" == "$ULTIMO_ANO" ]; then
				# Para o ano atual, busca de 01/01 até a data de hoje (formato MM/DD/YYYY)
				DATA_HOJE="$(date "+%m/%d/%Y")"
				echo "=> Baixando genomas do ano atual: $ANO (01-01 até $DATA_HOJE)" >> "$LOG_FILE"
				FILTRO_DATA="--released-after 01/01/${ANO} --released-before ${DATA_HOJE}"
			else
				echo "=> Baixando genomas do ano: $ANO (01-01 até 31-12)" >> "$LOG_FILE"
				FILTRO_DATA="--released-after 01/01/${ANO} --released-before 12/31/${ANO}"
			fi
			
			# Guardando mensagem de erro dentro de variavel para checar se ha genomas para essa requisicao
			MENSAGEM_ERRO="$(datasets download genome taxon "$TAXID" \
			--assembly-source "$BANCO_DADOS" \
			--exclude-atypical \
			$FILTRO_DATA \
			--dehydrated \
			--filename "$OUTPUT_ANO" \
			--no-progressbar 2>&1)"
			
			# Erro por falta de genoma
			if echo "$MENSAGEM_ERRO" | grep -q "Error: There are no genome assemblies that match your query"; then
				echo "[AVISO] Nenhum genoma encontrado para o TaxID $TAXID no ano $ANO. Pulando..." >> "$LOG_FILE"
				break
			# Checa outros possiveis erros 
			else 
				if checar_download_zip "$OUTPUT_ANO" ; then
					unzip -q "${OUTPUT_ANO}" -d "${DIR_OUTPUT_ANO}" 2>> "$LOG_FILE"
					echo "Download dos genomas desidratados de $TAXID do ano $ANO completo" >> "$LOG_FILE"
					break
				else
					echo "[ERRO] O download falhou ou o arquivo ZIP está corrompido." >> "$LOG_FILE"
					echo "[ERRO] Falha no Taxid $TAXID do ano $ANO" >> "$LOG_FILE"
					echo "[ERRO] Aguardando 10 segundos para reiniciar o download..." >> "$LOG_FILE"
					sleep 10
					{ echo "Limpando arquivos"; rm -rf --verbose "$OUTPUT_ANO" "$DIR_OUTPUT_ANO"; } >> "$LOG_FILE"
				fi
			fi
		done
	done
	
	# Concatenar os arquivos de cada ano em um unico diretorio
	# ARQUIVOS: dir_pai/ncbi_dataset/fetch.txt, dir_pai/ncbi_dataset/data/assembly_data_report.jsonl
	
	ARQUIVO_URL="fetch.txt"
	ARQUIVO_METADADOS="assembly_data_report.jsonl"
	mkdir -p "$DIR_OUTPUT/ncbi_dataset/data"
	
	# Busca os dois arquivos nas pastas dos anos e concatena no arquivo final
	echo "[INFO] Concatenando os arquivos $ARQUIVO_URL para ${DIR_OUTPUT}/ncbi_dataset/fetch.txt" >> "$LOG_FILE"
	find [0-9]*-"${DIR_OUTPUT}" -type f -name "$ARQUIVO_URL" -exec cat {} + > "${DIR_OUTPUT}/ncbi_dataset/fetch.txt"
	echo "[INFO] Concatenando os arquivos $ARQUIVO_METADADOS para ${DIR_OUTPUT}/ncbi_dataset/data/assembly_data_report.jsonl" >> "$LOG_FILE"
	find [0-9]*-"${DIR_OUTPUT}" -type f -name "$ARQUIVO_METADADOS" -exec cat {} + > "${DIR_OUTPUT}/ncbi_dataset/data/assembly_data_report.jsonl"
	
	echo "[INFO] Download dos genomas desidratados de $TAXID completo" >> "$LOG_FILE"
	
	# Removendo os diretorio e os arquivos zip dos anos
	rm -rf [0-9]*-"${OUTPUT}" [0-9]*-"${DIR_OUTPUT}"
}
