###### DOWNLOAD DOS BANCOS DE DADOS DE REFERENCIA (NCBI, GTDB, BACDIVE) ######
# Esses dados sao "globais" (nao dependem do taxon analisado na pipeline) e
# so precisam ser baixados uma unica vez. Ficam salvos fora do OUTPUT_DIR da
# execucao, num diretorio fixo de referencia
#
# Controle de instalacao: ao final do download dos TRES bancos (NCBI, GTDB
# e BacDive) com sucesso, e criado um arquivo COMPLETED.txt no diretorio raiz
# de referencia. Se esse arquivo existir, o download completo e pulado - a menos 
# que a flag --update-reference-databases seja usada, que forca a limpeza do 
# diretorio e um novo download do zero.

# --------------------------------------------------------------------------
# 1. NCBI - metadados desidratados de TODOS os procariotos (Bacteria + Archaea)
# --------------------------------------------------------------------------

# Uso: baixar_metadados_ncbi_procariotos <dir_referencia>
baixar_metadados_ncbi_procariotos () {
	local DIR_REFERENCIA="${1?}"
	local DIR_NCBI="${DIR_REFERENCIA}/NCBI"

	# Taxids fixos: 2 = Bacteria / 2157 = Archaea (NCBI Taxonomy)
	local VETOR_TAXID=( "2" "2157" )
	local VETOR_DOMINIO=( "Bacteria" "Archaea" )

	local ARQUIVO_URL="fetch.txt"
	local ARQUIVO_METADADOS="assembly_data_report.jsonl"

	for ((i=0; i<${#VETOR_TAXID[@]}; i++)); do
		local TAXID="${VETOR_TAXID[i]}"
		local DOMINIO="${VETOR_DOMINIO[i]}"
		local DIR_DOMINIO="${DIR_NCBI}/${DOMINIO}"
		local FETCH_FINAL="${DIR_DOMINIO}/${ARQUIVO_URL}"
		local JSON_FINAL="${DIR_DOMINIO}/${ARQUIVO_METADADOS}"

		# --- Idempotencia local: pula se ja foi baixado com sucesso antes ---
		# (protecao extra para retomar apos falha no meio dos 2 dominios,
		# mesmo sem o COMPLETED.txt global ter sido criado)
		if [[ -s "$FETCH_FINAL" && -s "$JSON_FINAL" ]]; then
			echo "[INFO] Metadados NCBI de $DOMINIO ja existem em $DIR_DOMINIO. Pulando download." >> "$LOG_FILE"
			continue
		fi

		mkdir -p "$DIR_DOMINIO" \
			|| { echo "[ERRO] Nao foi possivel criar diretorio $DIR_DOMINIO" >> "$LOG_FILE" ; return 1 ; }

		local DIR_TEMP_ANOS
		DIR_TEMP_ANOS=$(mktemp -d)

		local ANO_INICIAL="2017"
		local ULTIMO_ANO="$(date "+%Y")"
		local VETOR_ANOS=( $(seq -s' ' $ANO_INICIAL $ULTIMO_ANO) )

		if [[ -z "$NCBI_API_KEY" ]]; then
			echo "[WARNING] Variavel ambiente NCBI_API_KEY nao encontrada. Requisicoes ao NCBI podem ser mais lentas" >> "$LOG_FILE"
		fi

		echo "[INFO] Iniciando download dos metadados desidratados de $DOMINIO (TaxID $TAXID)" >> "$LOG_FILE"

		for ANO in "${VETOR_ANOS[@]}"; do
			local OUTPUT_ANO="${DIR_TEMP_ANOS}/${ANO}-${DOMINIO}.zip"
			local DIR_OUTPUT_ANO="${DIR_TEMP_ANOS}/${ANO}-${DOMINIO}"

			# LOOP DE TENTATIVAS (blindado contra quedas de conexao)
			while true; do
				local FILTRO_DATA
				if [ "$ANO" == "$ANO_INICIAL" ]; then
					FILTRO_DATA="--released-before 12/31/${ANO_INICIAL}"
				elif [ "$ANO" == "$ULTIMO_ANO" ]; then
					local DATA_HOJE="$(date "+%m/%d/%Y")"
					FILTRO_DATA="--released-after 01/01/${ANO} --released-before ${DATA_HOJE}"
				else
					FILTRO_DATA="--released-after 01/01/${ANO} --released-before 12/31/${ANO}"
				fi

				local MENSAGEM_ERRO
				MENSAGEM_ERRO="$(datasets download genome taxon "$TAXID" \
				--assembly-source "GenBank" \
				--exclude-atypical \
				$FILTRO_DATA \
				--dehydrated \
				--filename "$OUTPUT_ANO" \
				--no-progressbar 2>&1)"

				if echo "$MENSAGEM_ERRO" | grep -q "Error: There are no genome assemblies that match your query"; then
					echo "[AVISO] Nenhum genoma de $DOMINIO encontrado no ano $ANO. Pulando..." >> "$LOG_FILE"
					break
				else
					if checar_download_zip "$OUTPUT_ANO"; then
						unzip -q "$OUTPUT_ANO" -d "$DIR_OUTPUT_ANO" 2>> "$LOG_FILE"
						echo "[INFO] Download dos metadados de $DOMINIO do ano $ANO completo" >> "$LOG_FILE"
						break
					else
						echo "[ERRO] Download do ano $ANO ($DOMINIO) falhou ou ZIP corrompido. Retentando em 10s..." >> "$LOG_FILE"
						sleep 10
						rm -rf "$OUTPUT_ANO" "$DIR_OUTPUT_ANO"
					fi
				fi
			done
		done

		# Concatenando fetch.txt e assembly_data_report.jsonl de todos os anos
		> "$FETCH_FINAL"
		> "$JSON_FINAL"
		find "$DIR_TEMP_ANOS" -type f -name "$ARQUIVO_URL" -exec cat {} + > "$FETCH_FINAL"
		find "$DIR_TEMP_ANOS" -type f -name "$ARQUIVO_METADADOS" -exec cat {} + > "$JSON_FINAL"

		if [[ ! -s "$FETCH_FINAL" || ! -s "$JSON_FINAL" ]]; then
			echo "[ERRO] Falha ao concatenar os metadados finais de $DOMINIO" >> "$LOG_FILE"
			rm -rf "$DIR_TEMP_ANOS"
			return 1
		fi

		echo "[SUCESSO] Metadados NCBI de $DOMINIO salvos em $DIR_DOMINIO" >> "$LOG_FILE"
		rm -rf "$DIR_TEMP_ANOS"
	done
}

# --------------------------------------------------------------------------
# 2. GTDB - taxonomia completa de Bacteria e Archaea (release mais recente)
# --------------------------------------------------------------------------

# Uso: baixar_taxonomia_gtdb <dir_referencia> <gtdb_link>
baixar_taxonomia_gtdb () {
	local DIR_REFERENCIA="${1?}"
	local GTDB_DATABASE_LINK="${2?}"
	local DIR_GTDB="${DIR_REFERENCIA}/GTDB"

	local ARQUEIA_GZ="ar53_taxonomy.tsv.gz"
	local BACTERIA_GZ="bac120_taxonomy.tsv.gz"
	local ARQUEIA_TSV="${DIR_GTDB}/ar53_taxonomy.tsv"
	local BACTERIA_TSV="${DIR_GTDB}/bac120_taxonomy.tsv"
	local PROKARYOTE_TAXONOMY="${DIR_GTDB}/gtdb_prokaryote_taxonomy.tsv"

	# --- Idempotencia local ---
	if [[ -s "$ARQUEIA_TSV" && -s "$BACTERIA_TSV" && -s "$PROKARYOTE_TAXONOMY" ]]; then
		echo "[INFO] Taxonomia do GTDB ja existe em $DIR_GTDB. Pulando download." >> "$LOG_FILE"
		return 0
	fi

	mkdir -p "$DIR_GTDB" \
		|| { echo "[ERRO] Nao foi possivel criar diretorio $DIR_GTDB" >> "$LOG_FILE" ; return 1 ; }

	local GTDB_LINK_LIMPO="${GTDB_DATABASE_LINK%/}"
	local ARQUEIA_URL="${GTDB_LINK_LIMPO}/${ARQUEIA_GZ}"
	local BACTERIA_URL="${GTDB_LINK_LIMPO}/${BACTERIA_GZ}"

	echo "[INFO] Baixando taxonomia do GTDB (Archaea/Bacteria) de $GTDB_LINK_LIMPO" >> "$LOG_FILE"

	local ARQUEIA_TEMP="${DIR_GTDB}/${ARQUEIA_GZ}"
	local BACTERIA_TEMP="${DIR_GTDB}/${BACTERIA_GZ}"

	if ! wget -q "$ARQUEIA_URL" -O "$ARQUEIA_TEMP"; then
		echo "[ERRO] Falha ao baixar taxonomia de Archaea ($ARQUEIA_URL)" >> "$LOG_FILE"
		return 1
	fi
	if ! wget -q "$BACTERIA_URL" -O "$BACTERIA_TEMP"; then
		echo "[ERRO] Falha ao baixar taxonomia de Bacteria ($BACTERIA_URL)" >> "$LOG_FILE"
		rm -f "$ARQUEIA_TEMP"
		return 1
	fi

	# Descompactando cada arquivo separadamente
	zcat "$ARQUEIA_TEMP" > "$ARQUEIA_TSV" \
		|| { echo "[ERRO] Falha ao descompactar $ARQUEIA_TEMP" >> "$LOG_FILE" ; return 1 ; }
	zcat "$BACTERIA_TEMP" > "$BACTERIA_TSV" \
		|| { echo "[ERRO] Falha ao descompactar $BACTERIA_TEMP" >> "$LOG_FILE" ; return 1 ; }

	# Versao concatenada dos dois dominios
	cat "$ARQUEIA_TSV" "$BACTERIA_TSV" > "$PROKARYOTE_TAXONOMY"

	# Padronizando prefixos GB_GCA/RS_GCF -> GCA/GCF (mesma logica do modulo 8)
	sed -i 's/^RS_GCF/GCF/; s/^GB_GCA/GCA/' "$ARQUEIA_TSV" "$BACTERIA_TSV" "$PROKARYOTE_TAXONOMY"

	# Remove arquivos temporarios
	rm -f "$ARQUEIA_TEMP" "$BACTERIA_TEMP"
	echo "[SUCESSO] Taxonomia do GTDB salva em $DIR_GTDB" >> "$LOG_FILE"
}

# --------------------------------------------------------------------------
# 3. BacDive - dados de cultivo/fenotipo (via API, com curl puro - sem Python)
# --------------------------------------------------------------------------
# API v2 do BacDive: https://api.bacdive.dsmz.de/v2/fetch/<id1>;<id2>;...
# Nao exige credenciais desde fev/2026, mas se a conta exigir, exportar
# BACDIVE_USER e BACDIVE_PASSWORD antes de chamar esta funcao (usados com
# 'curl -u usuario:senha')
#
# Cada resposta da API traz um campo "count" com o numero de cepas
# encontradas naquele lote (pode ser < TAMANHO_LOTE, pois os IDs do BacDive
# tem lacunas). Cada lote e salvo em um arquivo JSON bruto separado.
#
# Testado empiricamente com lotes de 500 IDs sem erros de requisicao, entao
# a funcao e propositalmente simples: 1 requisicao por lote, sem retry.
# Idempotencia: se um arquivo de lote ja existe (execucao anterior), ele e
# pulado; se o download completo (ate ID_MAXIMO) ja foi concluido, a funcao
# inteira e pulada (marcador DOWNLOAD_COMPLETED.txt).

# Uso: baixar_dados_bacdive <dir_referencia> <id_maximo:OPCIONAL> <tamanho_lote:OPCIONAL>
baixar_dados_bacdive () {
	local DIR_REFERENCIA="${1?}"
	local ID_MAXIMO="${2:-200000}" # maior BacDive-ID a tentar buscar (IDs vao ate ~190000+)
	local TAMANHO_LOTE="${3:-500}" # quantidade de IDs por requisicao (separados por ';' na URL)

	local DIR_BACDIVE="${DIR_REFERENCIA}/BacDive"
	local DIR_JSON_BRUTO="${DIR_BACDIVE}/raw_json"
	local ARQUIVO_CONTAGEM="${DIR_BACDIVE}/total_cepas_baixadas.txt"
	local ARQUIVO_DOWNLOAD_COMPLETO="${DIR_BACDIVE}/DOWNLOAD_COMPLETED.txt"
	local URL_BASE="https://api.bacdive.dsmz.de/v2/fetch"

	mkdir -p "$DIR_JSON_BRUTO" \
		|| { echo "[ERRO] Nao foi possivel criar diretorio $DIR_JSON_BRUTO" >> "$LOG_FILE" ; return 1 ; }

	# --- Idempotencia: se o download ja foi concluido ate ID_MAXIMO, pula ---
	if [[ -f "$ARQUIVO_DOWNLOAD_COMPLETO" ]]; then
		echo "[INFO] Download bruto do BacDive ja concluido (marcado em $ARQUIVO_DOWNLOAD_COMPLETO). Pulando." >> "$LOG_FILE"
		return 0
	fi

	# --- Autenticacao opcional (so usada se as variaveis estiverem definidas) ---
	local OPCOES_AUTH=()
	[[ -n "${BACDIVE_USER:-}" ]] && OPCOES_AUTH=( -u "${BACDIVE_USER}:${BACDIVE_PASSWORD:-}" )

	echo "[INFO] Baixando metadados do BacDive (IDs 1 a $ID_MAXIMO, lotes de $TAMANHO_LOTE)" >> "$LOG_FILE"

	# 1. Vetor com todos os IDs de 1 a ID_MAXIMO
	local IDS_ARRAY
	mapfile -t IDS_ARRAY < <(seq 1 "$ID_MAXIMO")
	local TOTAL_IDS="${#IDS_ARRAY[@]}"

	# 2. Fatiando o vetor em lotes e disparando o curl em blocos
	local i INICIO_LOTE FIM_LOTE LOTE_IDS URL ARQUIVO_SAIDA_LOTE
	for (( i=0; i<TOTAL_IDS; i+=TAMANHO_LOTE )); do
		INICIO_LOTE=$(( i + 1 ))
		FIM_LOTE=$(( i + TAMANHO_LOTE < TOTAL_IDS ? i + TAMANHO_LOTE : TOTAL_IDS ))

		ARQUIVO_SAIDA_LOTE="${DIR_JSON_BRUTO}/bacdive_$(printf '%06d' "$INICIO_LOTE")_$(printf '%06d' "$FIM_LOTE").json"

		# Pula lote se ja foi baixado numa execucao anterior
		[[ -s "$ARQUIVO_SAIDA_LOTE" ]] && continue

		LOTE_IDS=$(IFS=';'; echo "${IDS_ARRAY[*]:i:TAMANHO_LOTE}")
		URL="${URL_BASE}/${LOTE_IDS}"

		curl -s -X GET "$URL" -H "Accept: application/json" "${OPCOES_AUTH[@]}" -o "$ARQUIVO_SAIDA_LOTE"

		[[ -s "$ARQUIVO_SAIDA_LOTE" ]] || echo "[AVISO] Lote ${INICIO_LOTE}-${FIM_LOTE} nao retornou dados" >> "$LOG_FILE"
	done

	# 3. Contagem total de cepas baixadas: soma do campo "count" de cada lote
	local TOTAL_BAIXADO
	TOTAL_BAIXADO="$(grep -Eo "\"count\":[0-9]+" "${DIR_JSON_BRUTO}"/*.json 2>/dev/null \
		| grep -oE '[0-9]+$' | awk '{soma+=$1} END{print soma+0}')"
	echo "$TOTAL_BAIXADO" > "$ARQUIVO_CONTAGEM"

	# So marca como concluido se nenhum lote ficou vazio (falho); assim, uma
	# proxima execucao tenta novamente so os lotes que faltaram
	local NUM_LOTES_VAZIOS
	NUM_LOTES_VAZIOS="$(find "$DIR_JSON_BRUTO" -type f -empty 2>/dev/null | wc -l)"

	if [[ "$NUM_LOTES_VAZIOS" -eq 0 ]]; then
		{
			echo "Download bruto do BacDive concluido em: $(date '+%Y-%m-%d %H:%M:%S')"
			echo "Total de cepas baixadas: ${TOTAL_BAIXADO}"
		} > "$ARQUIVO_DOWNLOAD_COMPLETO"
		echo "[SUCESSO] Download do BacDive concluido: ${TOTAL_BAIXADO} cepas (arquivos brutos em $DIR_JSON_BRUTO)" >> "$LOG_FILE"
	else
		echo "[AVISO] ${NUM_LOTES_VAZIOS} lote(s) nao retornaram dados. Rode novamente para tentar completa-los (lotes ja baixados sao pulados)" >> "$LOG_FILE"
	fi

	return 0
}

# --------------------------------------------------------------------------
# 3b. BacDive - conversao dos JSON brutos para TSV (foco: culture_medium)
# --------------------------------------------------------------------------
# [STATUS ATUAL] So extrai a subsecao 'culture_medium' (dentro da secao
# 'Culture and growth conditions'), alem do identificador da cepa e do(s)
# NCBI TaxID(s) associados (necessarios para cruzar com os genomas depois).
# Outras subsecoes (culture_pH, culture_temp, halophily, origin/isolamento,
# etc.) ainda nao sao extraidas - ver TODOs em Search-Genomes-Backend.sh
#
# Ambos os campos do BacDive (ex: "NCBI tax id" e "culture medium") podem
# vir como um OBJETO UNICO (quando ha so uma entrada) ou como um ARRAY
# (quando ha varias) - o filtro normaliza os dois casos. Quando ha mais de
# uma entrada, os valores de cada coluna sao concatenados com ';'.
#
# Uso: converter_bacdive_json_para_tsv <dir_json_bruto> <tsv_saida>
converter_bacdive_json_para_tsv () {
	local DIR_JSON_BRUTO="${1?}"
	local ARQUIVO_TSV_SAIDA="${2?}"

	if ! command -v jq &> /dev/null; then
		echo "[ERRO] Programa 'jq' nao encontrado no PATH (necessario para converter_bacdive_json_para_tsv)" >> "$LOG_FILE"
		return 1
	fi

	if ! ls "${DIR_JSON_BRUTO}"/*.json &> /dev/null; then
		echo "[ERRO] Nenhum arquivo JSON bruto encontrado em $DIR_JSON_BRUTO" >> "$LOG_FILE"
		return 1
	fi

	printf "BacDive_ID\tNCBI_TaxID\tMedium_Name\tMedium_Growth\tMedium_Link\tMedium_Composition\n" > "$ARQUIVO_TSV_SAIDA"

	# Filtro jq usado para cada arquivo de lote (um lote = varias cepas)
	local FILTRO_JQ='
		def normalizar_lista(x):
			if (x == null) then []
			elif (x | type) == "array" then x
			else [x] end;

		def join_ou_null(f):
			( [.[] | (f // "NULL") | tostring | gsub("[\t\n\r]";" ") ] ) as $arr
			| if ($arr | length) == 0 then "NULL" else ($arr | join(";")) end;

		(.results // {}) | to_entries[]? | .value as $strain |
		( $strain.General."BacDive-ID" // "NULL" ) as $bacdive_id |
		( normalizar_lista($strain.General."NCBI tax id"?) ) as $taxid_obj_lista |
		( [ $taxid_obj_lista[]."NCBI tax id"? ] ) as $taxid_lista |
		( if ($taxid_lista | length) == 0 then "NULL" else ($taxid_lista | map(tostring) | join(";")) end ) as $taxids |
		( normalizar_lista($strain."Culture and growth conditions"."culture medium"?) ) as $cm |
		[
			($bacdive_id | tostring),
			$taxids,
			($cm | join_ou_null(.name)),
			($cm | join_ou_null(.growth)),
			($cm | join_ou_null(.link)),
			($cm | join_ou_null(.composition))
		] | @tsv
	'

	local ARQUIVO_JSON NUM_ARQUIVOS_FALHOS=0
	for ARQUIVO_JSON in "${DIR_JSON_BRUTO}"/*.json; do
		[[ -s "$ARQUIVO_JSON" ]] || continue
		jq -r "$FILTRO_JQ" "$ARQUIVO_JSON" >> "$ARQUIVO_TSV_SAIDA" \
			|| { echo "[AVISO] Falha ao converter $ARQUIVO_JSON (pulando)" >> "$LOG_FILE" ; (( NUM_ARQUIVOS_FALHOS++ )) ; }
	done

	local NUM_CEPAS_CONVERTIDAS
	NUM_CEPAS_CONVERTIDAS=$(( $(wc -l < "$ARQUIVO_TSV_SAIDA") - 1 ))
	echo "[SUCESSO] Tabela de dados de cultivo (BacDive) gerada em $ARQUIVO_TSV_SAIDA (${NUM_CEPAS_CONVERTIDAS} cepas)" >> "$LOG_FILE"
	if [[ "$NUM_ARQUIVOS_FALHOS" -gt 0 ]]; then
		echo "[AVISO] ${NUM_ARQUIVOS_FALHOS} arquivo(s) de lote falharam na conversao" >> "$LOG_FILE"
	fi

	return 0
}

# --------------------------------------------------------------------------
# Funcao "guarda-chuva": controla instalacao/atualizacao dos 3 bancos
# --------------------------------------------------------------------------

# Uso: baixar_bancos_referencia <dir_referencia> <gtdb_link> <forcar_atualizacao:true/false>
baixar_bancos_referencia () {
	local DIR_REFERENCIA="${1?}"
	local GTDB_LINK="${2?}"
	local FORCAR_ATUALIZACAO="${3:-false}"

	local ARQUIVO_COMPLETED="${DIR_REFERENCIA}/COMPLETED.txt"

	# --- Flag --update-reference-databases: forca limpeza e novo download ---
	if [[ "$FORCAR_ATUALIZACAO" == "true" ]]; then
		echo "[INFO] Flag --update-reference-databases ativa. Forcando novo download dos bancos de referencia." >> "$LOG_FILE"
		if [[ -d "$DIR_REFERENCIA" ]]; then
			rm -rf "$DIR_REFERENCIA"
		fi
	fi

	# --- Verificacao de instalacao previa (mesma logica de marcacao do skDER) ---
	if [[ -f "$ARQUIVO_COMPLETED" ]]; then
		echo "[INFO] Bancos de referencia ja instalados (marcados em $ARQUIVO_COMPLETED). Pulando download." >> "$LOG_FILE"
		echo "[INFO] Use a flag --update-reference-databases para forcar a reinstalacao." >> "$LOG_FILE"
		return 0
	fi

	mkdir -p "$DIR_REFERENCIA" \
		|| { echo "[ERRO] Nao foi possivel criar diretorio $DIR_REFERENCIA" >> "$LOG_FILE" ; return 1 ; }

	# Removendo qualquer marcacao antiga/incompleta antes de tentar novamente
	rm -f "$ARQUIVO_COMPLETED"

	baixar_metadados_ncbi_procariotos "$DIR_REFERENCIA" \
		|| { echo "[ERRO] Falha no download dos metadados do NCBI" >> "$LOG_FILE" ; return 1 ; }

	baixar_taxonomia_gtdb "$DIR_REFERENCIA" "$GTDB_LINK" \
		|| { echo "[ERRO] Falha no download da taxonomia do GTDB" >> "$LOG_FILE" ; return 1 ; }

	baixar_dados_bacdive "$DIR_REFERENCIA" \
		|| { echo "[ERRO] Falha no download dos dados do BacDive" >> "$LOG_FILE" ; return 1 ; }

	converter_bacdive_json_para_tsv "${DIR_REFERENCIA}/BacDive/raw_json" "${DIR_REFERENCIA}/BacDive/bacdive_data.tsv" \
		|| { echo "[ERRO] Falha na conversao JSON->TSV dos dados do BacDive" >> "$LOG_FILE" ; return 1 ; }

	# Marcando conclusao SOMENTE apos os 3 downloads terem sucesso
	{
		echo "Download dos bancos de referencia concluido em: $(date '+%Y-%m-%d %H:%M:%S')"
		echo "NCBI: TaxID 2 (Bacteria) e TaxID 2157 (Archaea)"
		echo "GTDB: $GTDB_LINK"
		echo "BacDive: via API REST (curl), https://api.bacdive.dsmz.de/v2"
	} > "$ARQUIVO_COMPLETED"

	echo "[SUCESSO] Bancos de dados de referencia (NCBI, GTDB, BacDive) prontos em $DIR_REFERENCIA" >> "$LOG_FILE"
}

	# Arquivos gerados dentro de DIR_REFERENCIA:
	# NCBI/Bacteria/fetch.txt
	# NCBI/Bacteria/assembly_data_report.jsonl
	# NCBI/Archaea/fetch.txt
	# NCBI/Archaea/assembly_data_report.jsonl
	# GTDB/ar53_taxonomy.tsv
	# GTDB/bac120_taxonomy.tsv
	# GTDB/gtdb_prokaryote_taxonomy.tsv
	# BacDive/raw_json/bacdive_<inicio>_<fim>.json (um arquivo por lote baixado)
	# BacDive/bacdive_data.tsv (convertido - foco atual: subsecao culture_medium)
	# BacDive/total_cepas_baixadas.txt (soma do campo "count" de todos os lotes)
	# BacDive/DOWNLOAD_COMPLETED.txt (marca que o download bruto foi concluido)
	# COMPLETED.txt (criado apenas ao final, com sucesso dos 3 downloads)