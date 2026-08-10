# Funcao para converter os metadados dos genomas de JSON para TSV

###### VARIAVEIS GLOBAIS DE METADADOS ##########

# IMPORTANTE: os tres vetores abaixo devem manter a MESMA ORDEM entre si
# (o item i de um corresponde ao item i dos outros dois)

VETOR_NOMES_CAMPOS=(
    "ASSEMBLY"
    "SAMPLE"
    "GENERAL"
    "QUALITY"
)

VETOR_OUTPUT_METADADOS=(
    "ASSEMBLY-METADATA.tsv"
    "SAMPLE-METADATA.tsv"
    "GENERAL-METADATA.tsv"
    "QUALITY-METADATA.tsv"
)

VETOR_CAMPOS=(
	"accession,assminfo-notes,assminfo-type,assminfo-assembly-method,assminfo-level,assminfo-paired-assm-refseq-genbank-are-different,assminfo-release-date,assminfo-sequencing-tech"

	"accession,assminfo-biosample-accession,assminfo-biosample-collection-date,assminfo-biosample-cultivar,assminfo-biosample-description-organism-infraspecific-cultivar,assminfo-biosample-description-organism-infraspecific-ecotype,assminfo-biosample-description-organism-infraspecific-isolate,assminfo-biosample-description-organism-infraspecific-sex,assminfo-biosample-description-organism-infraspecific-strain,assminfo-biosample-ecotype,assminfo-biosample-geo-loc-name,assminfo-biosample-host,assminfo-biosample-host-disease,assminfo-biosample-ifsac-category,assminfo-biosample-isolate,assminfo-biosample-isolation-source,assminfo-biosample-lat-lon,assminfo-biosample-models,assminfo-biosample-project-name,assminfo-biosample-publication-date,assminfo-biosample-sample-name,assminfo-biosample-source-type,assminfo-biosample-strain,assminfo-biosample-sub-species,assminfo-biosample-submission-date"
	
	"accession,organism-tax-id,assminfo-biosample-isolation-source"
	
	"accession,assmstats-atgc-count,assmstats-contig-l50,assmstats-contig-n50,assmstats-gaps-between-scaffolds-count,assmstats-gc-percent,assmstats-genome-coverage,assmstats-number-of-component-sequences,assmstats-number-of-contigs,assmstats-number-of-scaffolds,assmstats-scaffold-l50,assmstats-scaffold-n50,assmstats-total-sequence-len,assmstats-total-ungapped-len,checkm-completeness,checkm-contamination"
)

# Funcao para converter os metadados dos genomas de JSON para TSV
# (ja aplicando a formatacao de valores nulos/ausentes)

# Uso: gerar_tabelas_metadados_tsv <metadados_json> <dir_output_metadados> <prefixo_genoma>
gerar_tabelas_metadados_tsv () {
	local METADADOS_JSON="${1?}"
	local DIR_OUTPUT_METADADOS="${2?}"
	local PREFIXO_GENOMA="${3?}"
	
	# Gerar diretorio de metadados e limpar antigos
	limpar_diretorio "$DIR_OUTPUT_METADADOS"
    
    # Checar arquivos de metadados JSON
    if [[ ! -f "$METADADOS_JSON" || ! -s "$METADADOS_JSON"  ]]; then
        echo "[ERRO] Arquivo de metadados em JSON '$METADADOS_JSON' invalido" >> "$LOG_FILE"
        return 1
    fi
	# Checar diretorio de output
	if [ ! -d "$DIR_OUTPUT_METADADOS" ]; then
		echo "[ERRO] Diretorio de metadados '$DIR_OUTPUT_METADADOS' invalido" >> "$LOG_FILE"
		return 1
	fi

	# Checar consistencia dos vetores globais (mesmo tamanho)
	if [[ "${#VETOR_CAMPOS[@]}" -ne "${#VETOR_OUTPUT_METADADOS[@]}" || "${#VETOR_CAMPOS[@]}" -ne "${#VETOR_NOMES_CAMPOS[@]}" ]]; then
		echo "[ERRO] Vetores globais de metadados com tamanhos diferentes (VETOR_CAMPOS=${#VETOR_CAMPOS[@]}, VETOR_OUTPUT_METADADOS=${#VETOR_OUTPUT_METADADOS[@]}, VETOR_NOMES_CAMPOS=${#VETOR_NOMES_CAMPOS[@]})" >> "$LOG_FILE"
		return 1
	fi
    
    # Convertendo os metadados dos campos selecionados para os respectivos arquivos,
	# ja aplicando a formatacao de valores nulos/ausentes
	local num_tabelas_metadados="${#VETOR_CAMPOS[@]}"
    for ((i=0; i<"$num_tabelas_metadados"; i++)); do
        local METADADOS_TEMP_BRUTO
        METADADOS_TEMP_BRUTO=$(mktemp)

        dataformat tsv genome \
        --inputfile "$METADADOS_JSON" \
        --fields "${VETOR_CAMPOS[i]}" \
        > "$METADADOS_TEMP_BRUTO" \
			|| { echo "[ERRO] Comando dataformat falhou para '${VETOR_OUTPUT_METADADOS[i]}'!" >> "$LOG_FILE" ; rm -f "$METADADOS_TEMP_BRUTO" ; return 1 ; }

		formatar_tabelas_metadados "$METADADOS_TEMP_BRUTO" \
			"${DIR_OUTPUT_METADADOS}/${VETOR_OUTPUT_METADADOS[i]}" \
			"$PREFIXO_GENOMA" \
			|| { echo "[ERRO] Funcao formatar_tabelas_metadados falhou para '${VETOR_OUTPUT_METADADOS[i]}'!" >> "$LOG_FILE" ; rm -f "$METADADOS_TEMP_BRUTO" ; return 1 ; }

		rm -f "$METADADOS_TEMP_BRUTO"
	done
	
	# Convertendo todos os campos de metadados para arquivo completo (sem flag --fields),
	# tambem formatado
	local COMPLETE_METADATA="ALL-METADATA.tsv"
	local METADADOS_TEMP_BRUTO_COMPLETO
	METADADOS_TEMP_BRUTO_COMPLETO=$(mktemp)

	dataformat tsv genome \
        --inputfile "$METADADOS_JSON" \
        > "$METADADOS_TEMP_BRUTO_COMPLETO" \
			|| { echo "[ERRO] Comando dataformat falhou!" >> "$LOG_FILE" ; rm -f "$METADADOS_TEMP_BRUTO_COMPLETO" ; return 1 ; }

	formatar_tabelas_metadados "$METADADOS_TEMP_BRUTO_COMPLETO" \
		"${DIR_OUTPUT_METADADOS}/${COMPLETE_METADATA}" \
		"$PREFIXO_GENOMA" \
		|| { echo "[ERRO] Funcao formatar_tabelas_metadados falhou para '${COMPLETE_METADATA}'!" >> "$LOG_FILE" ; rm -f "$METADADOS_TEMP_BRUTO_COMPLETO" ; return 1 ; }

	rm -f "$METADADOS_TEMP_BRUTO_COMPLETO"
}

# Funcao para substituir valores nulos/ausentes por "NULL" nas tabelas de metadados
# Uso: formatar_tabelas_metadados <tabela_nao_formatada> <tabela_formatada> <prefixo_genoma>
formatar_tabelas_metadados () {
	local TABELA_NAO_FORMATADA="${1?}"
	local TABELA_FORMATADA="${2?}"
	local PREFIXO_GENOMA="${3?}"

	# Regex numa unica linha, sem espacos/quebras dentro dos parenteses,
	# com os caracteres especiais de ERE escapados (. e -) e ancorada (^...$)
	# para so considerar nulo quando o CAMPO INTEIRO bater com o padrao.
	local REGEX_NULL_VALUES='^(null|na|n\/a|nd|n\/d|missing|not[ _-]?applicable|not[ _-]?provided|not[ _-]?collected|not[ _-]?available|not[ _-]?specified|not[ _-]?determined|not[ _-]?reported|not[ _-]?recorded|not[ _-]?informed|unknown|unspecified|none|no[ _-]?data|unavailable|undetermined|tbd|-+|\.+|empty)$'

	awk -F'\t' -v OFS='\t' -v prefixo="$PREFIXO_GENOMA" -v regex="$REGEX_NULL_VALUES" '
	{
		# Excluir linhas que nao iniciarem com o prefixo (ancorando corretamente)
		if ($0 !~ "^" prefixo) { next }

		for (i=1; i<=NF; i++) {
			valor = tolower($i)
			gsub(/^[ \t]+|[ \t]+$/, "", valor)  # remove espacos nas bordas antes de comparar
			if (valor ~ regex) {
				$i = "NULL"
			}
		}
		print $0
	}' "$TABELA_NAO_FORMATADA" > "$TABELA_FORMATADA" \
		|| { echo "[ERRO] Comando awk falhou!" >> "$LOG_FILE" ; return 1 ; }
}