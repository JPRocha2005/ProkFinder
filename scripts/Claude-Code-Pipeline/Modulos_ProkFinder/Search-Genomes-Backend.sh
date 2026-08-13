###### MODULO DE BUSCA DE GENOMAS (BACK-END) - search_genomes ######
#
# Funcoes responsaveis por cruzar os criterios informados pelo usuario
# (ja lidos/validados pelo front-end, em Search-Genomes-Frontend.sh) com as
# tabelas de metadados/taxonomia/fenotipo baixadas pelo modulo 0
# (0_Download-Databases-Referencia.sh) e retornar a lista de genomas
# (accession) que fazem match.
#
# [STATUS ATUAL] Apenas a ESTRUTURA das funcoes buscar_por_* esta pronta. A
# logica de busca propriamente dita depende de conversoes JSON->TSV que
# ainda precisam ser feitas/portadas:
#
#   1) assembly_data_report.jsonl (NCBI) -> TSV
#      Reaproveitar a logica de 'dataformat' ja usada no modulo antigo
#      2_Get-Metadata-Dehydrated-Genomes.sh (gerar_tabelas_metadados_tsv)
#      https://www.ncbi.nlm.nih.gov/datasets/docs/v2/reference-docs/command-line/dataformat/
#
#   2) bacdive_data.jsonl (BacDive) -> TSV
#      [JA IMPLEMENTADO, PARCIAL] O download bruto (via curl, API v2 do
#      BacDive) e a conversao JSON->TSV agora sao feitos em bash puro pelas
#      funcoes baixar_dados_bacdive() e converter_bacdive_json_para_tsv(),
#      definidas em 0_Download-Databases-Referencia.sh. Por enquanto, a
#      conversao extrai APENAS a subsecao 'culture_medium' (nome do meio,
#      crescimento, link e composicao) + BacDive-ID + NCBI TaxID associado.
#      Outras subsecoes do BacDive (culture_pH, culture_temp, halophily,
#      origin/isolamento, etc. - usadas por buscar_por_fenotipo, buscar_por_
#      pais e buscar_por_fonte_isolamento abaixo) AINDA NAO sao extraidas.
#      Referencia dos campos/estrutura do JSON: BacDive API (DSMZ)
#      https://api.bacdive.dsmz.de/
#
# Enquanto a busca em si (grep/awk nas tabelas TSV) nao existe, as funcoes
# buscar_por_* abaixo apenas registram um aviso de "nao implementado" e
# devolvem um arquivo temporario vazio, para que o front-end possa ser
# desenvolvido/testado de forma independente do back-end (e para deixar
# clara a assinatura/formato de entrada e saida esperado de cada uma).
#
# CONTRATO de cada funcao buscar_por_*:
#   Entrada: o(s) valor(es) do criterio (ja validado pelo front-end)
#   Saida:   imprime (via echo) o CAMINHO de um arquivo temporario contendo
#            uma lista de accessions de genomas (um por linha, sem header)
#            que atendem aquele criterio, isoladamente.
# A funcao executar_busca_genomas faz a INTERSECAO desses arquivos.


################################################################################
# CAMINHOS DAS TABELAS DE REFERENCIA
################################################################################

# Preenche as variaveis globais com os caminhos das tabelas usadas na busca.
# Depende de DIR_REFERENCIA (definido em Claude-Main-Hub.sh)
definir_caminhos_busca () {
	NCBI_METADATA_TSV_BACTERIA="${DIR_REFERENCIA}/NCBI/Bacteria/METADATA-TSV/ALL-METADATA.tsv"
	NCBI_METADATA_TSV_ARCHAEA="${DIR_REFERENCIA}/NCBI/Archaea/METADATA-TSV/ALL-METADATA.tsv"
	GTDB_TAXONOMY_TSV="${DIR_REFERENCIA}/GTDB/gtdb_prokaryote_taxonomy.tsv" # SEM header (accession, taxonomia)
	BACDIVE_TSV="${DIR_REFERENCIA}/BacDive/bacdive_data.tsv"                # TODO: ainda nao gerado
}


################################################################################
# CONVERSAO JSON -> TSV (ainda nao implementada para fins de busca)
################################################################################

# Uso: converter_ncbi_json_para_tsv <assembly_data_report.jsonl> <dir_saida>
# TODO: portar/reaproveitar gerar_tabelas_metadados_tsv() do modulo antigo
# 2_Get-Metadata-Dehydrated-Genomes.sh (usa 'dataformat tsv genome'), gerando
# o arquivo <dir_saida>/ALL-METADATA.tsv usado por NCBI_METADATA_TSV_*
converter_ncbi_json_para_tsv () {
	local METADADOS_JSON="${1?}"
	local DIR_SAIDA="${2?}"
	log_aviso "[NAO IMPLEMENTADO] converter_ncbi_json_para_tsv ($METADADOS_JSON -> $DIR_SAIDA)"
	return 0
}

# converter_bacdive_json_para_tsv() NAO esta mais definida aqui - agora vive
# em 0_Download-Databases-Referencia.sh (ja carregado antes deste modulo via
# carregar_modulo_referencia, chamado dentro de baixar_bancos_referencia).
# Por enquanto ela extrai apenas a subsecao 'culture_medium' (ver cabecalho
# deste arquivo). Os campos de temperatura/pH/salinidade/pais/isolamento
# usados por buscar_por_fenotipo/buscar_por_pais/buscar_por_fonte_isolamento
# ainda precisam ser adicionados a essa conversao no futuro.


################################################################################
# FUNCOES DE BUSCA POR CRITERIO (cada uma retorna o caminho de um arquivo
# temporario com a lista de accessions que atendem aquele criterio)
################################################################################

buscar_por_organismo () {
	local TERMO_BUSCA="${1?}"
	local ARQUIVO_TEMP; ARQUIVO_TEMP="$(mktemp)"
	# TODO: grep -i "$TERMO_BUSCA" na coluna "Organism Name" de
	# NCBI_METADATA_TSV_BACTERIA / NCBI_METADATA_TSV_ARCHAEA, imprimindo a
	# coluna de accession (1a coluna) dos genomas que derem match
	log_aviso "[NAO IMPLEMENTADO] buscar_por_organismo: '$TERMO_BUSCA'"
	echo "$ARQUIVO_TEMP"
}

buscar_por_taxid_ncbi () {
	local TAXID="${1?}"
	local ARQUIVO_TEMP; ARQUIVO_TEMP="$(mktemp)"
	# TODO: awk -F'\t' na coluna "organism-tax-id" (GENERAL-METADATA.tsv)
	# comparando com $TAXID (match exato)
	log_aviso "[NAO IMPLEMENTADO] buscar_por_taxid_ncbi: '$TAXID'"
	echo "$ARQUIVO_TEMP"
}

buscar_por_taxonomia_gtdb () {
	local TAXONOMIA="${1?}"
	local ARQUIVO_TEMP; ARQUIVO_TEMP="$(mktemp)"
	# TODO: se $TAXONOMIA contiver ';' tratar como taxonomia completa
	# (match exato na 2a coluna de GTDB_TAXONOMY_TSV); caso contrario,
	# tratar como um unico rank (ex: "g__Bacillus") e fazer match parcial
	# dentro da string de taxonomia (grep -F)
	log_aviso "[NAO IMPLEMENTADO] buscar_por_taxonomia_gtdb: '$TAXONOMIA'"
	echo "$ARQUIVO_TEMP"
}

buscar_por_taxonomia_ncbi () {
	local TAXONOMIA="${1?}"
	local ARQUIVO_TEMP; ARQUIVO_TEMP="$(mktemp)"
	# TODO: depende de um campo de taxonomia do NCBI nos metadados (nao
	# incluido nos campos baixados atualmente pelo dataformat - avaliar
	# adicionar 'organism-name' completo com linhagem, se disponivel)
	log_aviso "[NAO IMPLEMENTADO] buscar_por_taxonomia_ncbi: '$TAXONOMIA'"
	echo "$ARQUIVO_TEMP"
}

buscar_por_pais () {
	local PAIS="${1?}"
	local ARQUIVO_TEMP; ARQUIVO_TEMP="$(mktemp)"
	# TODO: coluna "assminfo-biosample-geo-loc-name" (SAMPLE-METADATA.tsv),
	# considerando que o valor costuma vir no formato "Pais: regiao/local"
	log_aviso "[NAO IMPLEMENTADO] buscar_por_pais: '$PAIS'"
	echo "$ARQUIVO_TEMP"
}

buscar_por_fonte_isolamento () {
	local FONTE="${1?}"
	local ARQUIVO_TEMP; ARQUIVO_TEMP="$(mktemp)"
	# TODO: coluna "assminfo-biosample-isolation-source" (GENERAL-METADATA.tsv
	# ou SAMPLE-METADATA.tsv), match parcial case-insensitive (mesma logica
	# de regex usada em add_category_metadata, modulo antigo 4)
	log_aviso "[NAO IMPLEMENTADO] buscar_por_fonte_isolamento: '$FONTE'"
	echo "$ARQUIVO_TEMP"
}

buscar_por_tipo_genoma () {
	local TIPO="${1?}" # isolado | mag
	local ARQUIVO_TEMP; ARQUIVO_TEMP="$(mktemp)"
	# TODO: coluna "assminfo-type" (ASSEMBLY-METADATA.tsv). Mapear
	# TIPO "isolado" -> valor NCBI (ex: "isolate") e "mag" -> "mag"
	log_aviso "[NAO IMPLEMENTADO] buscar_por_tipo_genoma: '$TIPO'"
	echo "$ARQUIVO_TEMP"
}

buscar_por_nivel_assembly () {
	local NIVEL="${1?}" # contig | scaffold | chromosome | complete_genome
	local ARQUIVO_TEMP; ARQUIVO_TEMP="$(mktemp)"
	# TODO: coluna "assminfo-level" (ASSEMBLY-METADATA.tsv), mapeando os
	# valores de SG_NIVEIS_ASSEMBLY_VALIDOS para os valores usados pelo NCBI
	# (ex: "Complete Genome", "Chromosome", "Scaffold", "Contig")
	log_aviso "[NAO IMPLEMENTADO] buscar_por_nivel_assembly: '$NIVEL'"
	echo "$ARQUIVO_TEMP"
}

# Uso: buscar_por_fenotipo <temperatura|ph|salinidade> <operador> <valor>
buscar_por_fenotipo () {
	local CAMPO="${1?}"
	local OPERADOR="${2?}"
	local VALOR="${3?}"
	local ARQUIVO_TEMP; ARQUIVO_TEMP="$(mktemp)"
	# TODO: filtrar BACDIVE_TSV pela coluna correspondente a $CAMPO,
	# aplicando $OPERADOR sobre $VALOR. Esboco futuro (awk nao aceita o
	# operador como string diretamente, precisa de if/elif ou eval):
	#   awk -F'\t' -v col=N -v valor="$VALOR" '
	#       NR>1 {
	#           if ($col == "NULL") next
	#           if ( ($col OPERADOR_LITERAL valor) ) print accession_col
	#       }' "$BACDIVE_TSV"
	log_aviso "[NAO IMPLEMENTADO] buscar_por_fenotipo: $CAMPO $OPERADOR $VALOR"
	echo "$ARQUIVO_TEMP"
}


################################################################################
# INTERSECAO DOS FILTROS E ORQUESTRACAO DA BUSCA
################################################################################

# Uso: intersectar_arquivos_accessions <arquivo_saida> <arquivo1> <arquivo2> ...
intersectar_arquivos_accessions () {
	local ARQUIVO_SAIDA="${1?}"; shift
	local ARQUIVOS=( "$@" )

	if [[ "${#ARQUIVOS[@]}" -eq 1 ]]; then
		sort -u "${ARQUIVOS[0]}" > "$ARQUIVO_SAIDA"
		return 0
	fi

	# comm -12 exige arquivos ordenados; feito par a par de forma acumulativa
	local ACUMULADO; ACUMULADO="$(mktemp)"
	sort -u "${ARQUIVOS[0]}" > "$ACUMULADO"

	local ARQ TEMP
	for ARQ in "${ARQUIVOS[@]:1}"; do
		TEMP="$(mktemp)"
		comm -12 "$ACUMULADO" <(sort -u "$ARQ") > "$TEMP"
		mv "$TEMP" "$ACUMULADO"
	done

	mv "$ACUMULADO" "$ARQUIVO_SAIDA"
}

# Uso: executar_busca_genomas <arquivo_saida>
# Le os criterios das variaveis globais SG_* (preenchidas pelo front-end),
# chama a funcao buscar_por_* correspondente a cada criterio informado e
# grava em <arquivo_saida> a intersecao (AND) de todos os filtros ativos
executar_busca_genomas () {
	local ARQUIVO_SAIDA="${1?}"

	definir_caminhos_busca

	local ARQUIVOS_FILTROS=()

	[[ -n "$SG_ORGANISMO" ]]        && ARQUIVOS_FILTROS+=( "$(buscar_por_organismo "$SG_ORGANISMO")" )
	[[ -n "$SG_TAXID_NCBI" ]]       && ARQUIVOS_FILTROS+=( "$(buscar_por_taxid_ncbi "$SG_TAXID_NCBI")" )
	[[ -n "$SG_TAXONOMIA_GTDB" ]]   && ARQUIVOS_FILTROS+=( "$(buscar_por_taxonomia_gtdb "$SG_TAXONOMIA_GTDB")" )
	[[ -n "$SG_TAXONOMIA_NCBI" ]]   && ARQUIVOS_FILTROS+=( "$(buscar_por_taxonomia_ncbi "$SG_TAXONOMIA_NCBI")" )
	[[ -n "$SG_PAIS" ]]             && ARQUIVOS_FILTROS+=( "$(buscar_por_pais "$SG_PAIS")" )
	[[ -n "$SG_FONTE_ISOLAMENTO" ]] && ARQUIVOS_FILTROS+=( "$(buscar_por_fonte_isolamento "$SG_FONTE_ISOLAMENTO")" )
	[[ -n "$SG_TIPO_GENOMA" ]]      && ARQUIVOS_FILTROS+=( "$(buscar_por_tipo_genoma "$SG_TIPO_GENOMA")" )
	[[ -n "$SG_NIVEL_ASSEMBLY" ]]   && ARQUIVOS_FILTROS+=( "$(buscar_por_nivel_assembly "$SG_NIVEL_ASSEMBLY")" )
	[[ -n "$SG_TEMP_VALOR" ]]       && ARQUIVOS_FILTROS+=( "$(buscar_por_fenotipo "temperatura" "$SG_TEMP_OPERADOR" "$SG_TEMP_VALOR")" )
	[[ -n "$SG_PH_VALOR" ]]         && ARQUIVOS_FILTROS+=( "$(buscar_por_fenotipo "ph" "$SG_PH_OPERADOR" "$SG_PH_VALOR")" )
	[[ -n "$SG_SALINIDADE_VALOR" ]] && ARQUIVOS_FILTROS+=( "$(buscar_por_fenotipo "salinidade" "$SG_SALINIDADE_OPERADOR" "$SG_SALINIDADE_VALOR")" )

	if [[ "${#ARQUIVOS_FILTROS[@]}" -eq 0 ]]; then
		log_erro "Nenhum criterio de busca informado em executar_busca_genomas"
		return 1
	fi

	intersectar_arquivos_accessions "$ARQUIVO_SAIDA" "${ARQUIVOS_FILTROS[@]}"
	local STATUS=$?

	rm -f "${ARQUIVOS_FILTROS[@]}"
	return "$STATUS"
}


################################################################################
# EXPORTACAO DAS TABELAS (metadados / taxonomia / dados de cultivo) DOS HITS
################################################################################
# Essa parte JA usa uma implementacao real (nao e um TODO): assim que as
# tabelas de origem (NCBI_METADATA_TSV_*, GTDB_TAXONOMY_TSV, BACDIVE_TSV)
# existirem, a exportacao dos hits ja funciona sem alteracoes.

# Uso: filtrar_tsv_por_lista_accessions <tsv_origem> <lista_accessions> <tsv_saida> <tem_header:true|false>
filtrar_tsv_por_lista_accessions () {
	local ARQUIVO_TSV_ORIGEM="${1?}"
	local LISTA_ACCESSIONS="${2?}"
	local ARQUIVO_TSV_SAIDA="${3?}"
	local TEM_HEADER="${4:-true}"

	if [[ ! -f "$ARQUIVO_TSV_ORIGEM" ]]; then
		log_aviso "Tabela de origem nao encontrada: $ARQUIVO_TSV_ORIGEM (pulando exportacao)"
		return 0
	fi
	if [[ ! -s "$LISTA_ACCESSIONS" ]]; then
		log_aviso "Nenhum genoma para filtrar em $ARQUIVO_TSV_ORIGEM"
		return 0
	fi

	if [[ "$TEM_HEADER" == "true" ]]; then
		head -n 1 "$ARQUIVO_TSV_ORIGEM" > "$ARQUIVO_TSV_SAIDA"
		tail -n +2 "$ARQUIVO_TSV_ORIGEM" | grep -F -f "$LISTA_ACCESSIONS" >> "$ARQUIVO_TSV_SAIDA" || true
	else
		> "$ARQUIVO_TSV_SAIDA"
		grep -F -f "$LISTA_ACCESSIONS" "$ARQUIVO_TSV_ORIGEM" >> "$ARQUIVO_TSV_SAIDA" || true
	fi
}

# Uso: exportar_metadados_hits <lista_accessions> <tsv_saida>
exportar_metadados_hits () {
	local ARQUIVO_RESULTADOS="${1?}"
	local ARQUIVO_SAIDA="${2?}"
	definir_caminhos_busca

	# Combina Bacteria + Archaea (mantendo so 1 header) antes de filtrar
	local ORIGEM_COMBINADA; ORIGEM_COMBINADA="$(mktemp)"
	awk 'FNR==1 && NR!=1 {next} {print}' \
		"$NCBI_METADATA_TSV_BACTERIA" "$NCBI_METADATA_TSV_ARCHAEA" \
		> "$ORIGEM_COMBINADA" 2>/dev/null

	filtrar_tsv_por_lista_accessions "$ORIGEM_COMBINADA" "$ARQUIVO_RESULTADOS" "$ARQUIVO_SAIDA" "true"
	rm -f "$ORIGEM_COMBINADA"
}

# Uso: exportar_taxonomia_hits <lista_accessions> <tsv_saida>
exportar_taxonomia_hits () {
	local ARQUIVO_RESULTADOS="${1?}"
	local ARQUIVO_SAIDA="${2?}"
	definir_caminhos_busca
	# gtdb_prokaryote_taxonomy.tsv nao tem header (ver modulo 0 e 8)
	filtrar_tsv_por_lista_accessions "$GTDB_TAXONOMY_TSV" "$ARQUIVO_RESULTADOS" "$ARQUIVO_SAIDA" "false"
}

# Uso: exportar_dados_cultivo_hits <lista_accessions> <tsv_saida>
exportar_dados_cultivo_hits () {
	local ARQUIVO_RESULTADOS="${1?}"
	local ARQUIVO_SAIDA="${2?}"
	definir_caminhos_busca
	# TODO: depende de converter_bacdive_json_para_tsv (ainda nao implementada)
	filtrar_tsv_por_lista_accessions "$BACDIVE_TSV" "$ARQUIVO_RESULTADOS" "$ARQUIVO_SAIDA" "true"
}
