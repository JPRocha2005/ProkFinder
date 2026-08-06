# Funcao para filtrar genomas de baixa qualidade	

# Uso: filtrar_genomas_pela_qualidade <tabela_qualidade_genomas> <max_contigs> <min_cobertura> <min_n50>

filtrar_genomas_pela_qualidade () {
	local TABELA_QUALIDADE="${1?}"
	local MAX_CONTIGS="${2?}"
	local MIN_COBERTURA="${3?}"
	local MIN_N50="${4?}"
	local LISTA_ACESSO_GENOMAS="${5?}"
	
	# Verificar arquivos antes da execucao
	if [ ! -f "$TABELA_QUALIDADE" ]; then
		echo "[ERRO] Arquivo $TABELA_QUALIDADE nao encontrado!" >> "$LOG_FILE"
		return 1
	fi
	if [ -z "$LISTA_ACESSO_GENOMAS" ]; then
		echo "[ERRO] Variavel 'LISTA_ACESSO_GENOMAS' vazia!" >> "$LOG_FILE"
		return 1
	else
		> "$LISTA_ACESSO_GENOMAS"
	fi
	
	# CAMPOS_QUALIDADE="accession,assmstats-atgc-count,assmstats-contig-l50,assmstats-contig-n50,assmstats-gaps-between-scaffolds-count,assmstats-gc-percent,assmstats-genome-coverage,assmstats-number-of-component-sequences,assmstats-number-of-contigs,assmstats-number-of-scaffolds,assmstats-scaffold-l50,assmstats-scaffold-n50,assmstats-total-sequence-len,assmstats-total-ungapped-len,checkm-completeness,checkm-contamination"
	
	# Tabela de metadados de qualidade:
	# 1) accession	Assembly Accession
	# 2) assmstats-atgc-count	Assembly Stats ATGC Count
	# 3) assmstats-contig-l50	Assembly Stats Contig L50
	# 4) assmstats-contig-n50	Assembly Stats Contig N50
	# 5) assmstats-gaps-between-scaffolds-count	Assembly Stats Gaps Between Scaffolds Count
	# 6) assmstats-gc-percent	Assembly Stats GC Percent
	# 7) assmstats-genome-coverage	Assembly Stats Genome Coverage
	# 8) assmstats-number-of-component-sequences	Assembly Stats Number of Component Sequences
	# 9) assmstats-number-of-contigs	Assembly Stats Number of Contigs
	# 10) assmstats-number-of-scaffolds	Assembly Stats Number of Scaffolds
	# 11) assmstats-scaffold-l50	Assembly Stats Scaffold L50
	# 12) assmstats-scaffold-n50	Assembly Stats Scaffold N50
	# 13) assmstats-total-sequence-len	Assembly Stats Total Sequence Length
	# 14) assmstats-total-ungapped-len	Assembly Stats Total Ungapped Length
	# 15) checkm-completeness	CheckM completeness
	# 16) checkm-contamination	CheckM contamination
	
	awk -F'\t' -v max_contigs="$MAX_CONTIGS" \
	-v min_cobertura="$MIN_COBERTURA" \
	-v min_n50="$MIN_N50" \
	-v lista_genomas="$LISTA_ACESSO_GENOMAS" '
	
	NR > 1 { # pulo o HEADER
		
		num_contigs = $9
		cobertura = $7
		n50 = $4
		
		# Valida cada critério: aceita se estiver NULL OU se passar na regra numérica
		cond_contigs = (num_contigs == "NULL" || num_contigs <= max_contigs)
		cond_cobertura = (cobertura == "NULL" || cobertura >= min_cobertura)
		cond_n50 = (n50 == "NULL" || n50 >= min_n50)
		
		# Se os 3 critérios forem atendidos, imprimir acesso do genoma na lista
		if (cond_contigs && cond_cobertura && cond_n50) {
			print $1 >> lista_genomas
		}
		
	}' "$TABELA_QUALIDADE" \
		|| { echo "[ERRO] Comando awk falhou!" >> "$LOG_FILE" ; return 1 ; }
}
	
