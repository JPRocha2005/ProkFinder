# Funcao para contar o numero regioes (gaps) de N's por contig do genoma
# e selecionar os genomas com numero aceitavel de gaps 

# Uso: filtrar_genomas_muitos_gaps <dir_fasta_genomas> <numero_cpus> <diretorio_output> <extensao_genomas:.fna:.gz>  
# <lista_genomas_poucos_gaps> <tam_min_gap> <num_max_gaps>
filtrar_genomas_muitos_gaps () {
	local PASTA_GENOMAS="${1?}"
	local NUMERO_CPU="${2?}"
	local DIR_OUTPUT_SEQKIT="${3?}"
	local EXTENSAO_ARQUIVO_GENOMA="${4?}"
	local LISTA_GENOMAS_FILTRADOS="${5?}"
	local TAMANHO_MINIMO_GAP="${6?}"
	local MAX_GAPS_PERMITIDO="${7?}"
	
	# Limpando dir antigo e criando novo dir de output para os resultados do seqkit
	if [ -d "$DIR_OUTPUT_SEQKIT" ]; then
		rm -rf "$DIR_OUTPUT_SEQKIT" && mkdir -p "$DIR_OUTPUT_SEQKIT"
	else
		mkdir -p "$DIR_OUTPUT_SEQKIT"
	fi
	
	# Criando lista de genomas filtrados para receber os genomas filtrados
	> "$LISTA_GENOMAS_FILTRADOS"
	
	# Criando arquivo com a lista de caminhos dos genomas
	local LISTA_GENOMAS=$(mktemp)
	find "$PASTA_GENOMAS" -maxdepth 1 -name "*.$EXTENSAO_ARQUIVO_GENOMA" > "$LISTA_GENOMAS" \
	|| { echo "[ERRO] Nao foi possivel encontrar os genomas em $PASTA_GENOMAS" >> "$LOG_FILE" ; return 1 ; }

	# Adicionando id dos genomas na lista
	local LISTA_GENOMAS_COM_ID=$(mktemp)
	awk -F'\t' '{
		caminho = $0
		if (match(caminho, /GC[AF]_[0-9]+\.[0-9]+/)) {
			id = substr(caminho, RSTART, RLENGTH)
		} else {
			id = "NULL"
		}
		print id "\t" caminho
	}' "$LISTA_GENOMAS" > "$LISTA_GENOMAS_COM_ID"
	
	# Relatorio com o numero de gaps dos contigs de cada genoma 
	local RELATORIO_GAPS_N_POR_CONTIG="${DIR_OUTPUT_SEQKIT}/contagem-gaps-n-por-contig.txt"
	echo -e "ID_Genoma\tID_Contig\tNum_Gaps\tTotal_Bases_N" > "$RELATORIO_GAPS_N_POR_CONTIG"

	# seqkit locate: localiza as posicoes de um padrao (regex ou motivo) na sequencia
	# INPUT: Genoma FASTA/Q (.fna ou .gz)
	# OUTPUT: Tabela tsv -> seqID, patternName, pattern, strand, start, end (1-based, inclusive)
	# Flags do seqkit locate
	# -r, --use-regexp: interpreta o padrao como expressao regular
	# -p, --pattern string: padrao de busca ("N+" localiza qualquer trecho contiguo de N's,
	# -i, --ignore-case: ignora maisculo e minusculo (trata 'N' e 'n' igualmente)
	# -j, --threads int: Numero de CPU (default: 4)
	# --hide-matched: nao mostra a ultima coluna com o padrao que deu match
	# --only-positive-strand: So faz a contagem na fita positiva (ignora a fita complementar)

	# Loop para ler cada genoma da lista e avaliar numero de gaps em cada contig
	# Preciso avaliar genoma por genoma para saber a origem do contig 
	while IFS=$'\t' read -r ID_GENOMA CAMINHO_GENOMA; do
		
		# Conta os gaps (>=50pb) agrupados por contig (coluna 1 = seqID)
		# e identifica o contig com o MAIOR numero de gaps naquele genoma
		local TEMP_SEQKIT_OUTPUT
		TEMP_SEQKIT_OUTPUT=$(mktemp)

		# Comando para identificar as sequencias de bases N no genoma
		seqkit locate \
			--use-regexp \
			--pattern "N+" \
			--hide-matched \
			--only-positive-strand \
			--ignore-case \
			--threads "$NUMERO_CPU" \
			"$CAMINHO_GENOMA" > "$TEMP_SEQKIT_OUTPUT" \
			|| { echo "[ERRO] Comando seqkit locate falhou!" >> "$LOG_FILE" ; return 1 ; }

		# Comando awk para analisar o numero de gaps no genoma e guardar seu id na lista,
		# caso esteja dentro dos criterios TAMANHO_MINIMO_GAP e MAX_GAPS_PERMITIDO
		awk -F'\t' -v tam_min_gap="$TAMANHO_MINIMO_GAP" \
			-v max_gaps_contig="$MAX_GAPS_PERMITIDO" \
			-v id_genoma="$ID_GENOMA" \
			-v out_relatorio_gaps_contig="$RELATORIO_GAPS_N_POR_CONTIG" \
			-v lista_genomas="$LISTA_GENOMAS_FILTRADOS" '
			BEGIN {
				total_linhas = 0
			}
			NR > 1 {
				total_linhas++
				id_sequencia = $1
				inicio_n = $5
				fim_n = $6

				chave_gap = id_sequencia "_" fim_n
				if (chave_gap in gaps_vistos) next
				gaps_vistos[chave_gap] = 1

				numero_bases_n = fim_n - inicio_n + 1
				if (numero_bases_n >= tam_min_gap) {
					count_gaps_per_contig[id_sequencia]++
				}
				total_bases_n_per_contig[id_sequencia] += numero_bases_n
			}
			END {
				genoma_valido = 1

				if (total_linhas == 0) {
					# Genoma sem nenhuma base N em nenhum contig
					# TABELA: id_genoma, id_contig=NULL, num_gaps=0, num_n=0
					print id_genoma "\t" "NULL" "\t" 0 "\t" 0 >> out_relatorio_gaps_contig
				} else {
					for (contig_id in count_gaps_per_contig) {
						number_gaps = count_gaps_per_contig[contig_id]
						total_n = total_bases_n_per_contig[contig_id]
						print id_genoma "\t" contig_id "\t" number_gaps "\t" total_n >> out_relatorio_gaps_contig
						if (number_gaps > max_gaps_contig) {
							genoma_valido = 0
						}
					}
				}

				if (genoma_valido == 1) {
					print id_genoma >> lista_genomas
					num_genomas_validos++
				}
			}' "$TEMP_SEQKIT_OUTPUT" \
				|| { echo "[ERRO] Comando awk para selecao de genomas com muitos gaps falhou!" >> "$LOG_FILE" ; return 1 ; }

		rm -f "$TEMP_SEQKIT_OUTPUT"
	done < "$LISTA_GENOMAS_COM_ID"
	
	local NUM_GENOMAS="$(wc -l $LISTA_GENOMAS_COM_ID)"
	local NUM_GENOMAS_VALIDOS="$(wc -l "$LISTA_GENOMAS_FILTRADOS")"
	echo "[INFO] Filtragem dos genomas por numero de GAPS finalizada" >> "$LOG_FILE"
	echo "[INFO] Numero de genomas avaliados: $NUM_GENOMAS"  >> "$LOG_FILE"
	echo "[INFO] Numero de genomas validos: $NUM_GENOMAS_VALIDOS" >> "$LOG_FILE"
	
	# Limpar os outros arq temp
	rm -f "$LISTA_GENOMAS" "$LISTA_GENOMAS_COM_ID" 
}