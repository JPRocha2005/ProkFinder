# Funcao para calcular a qualidade dos genomas (contaminacao e completude) utilizando o programa proprio para procariotos - CheckM2 

# Uso: filtrar_genomas_pelo_checkm2 <dir_fasta_genomas> <numero_cpus> <diretorio_output> <extensao_arquivo_genomas:.fna:.gz> 
# <min_completude> <max_contaminacao> <lista_genomas_alta_qualidade>

filtrar_genomas_pelo_checkm2 () {
	local PASTA_GENOMAS="${1?}"
	local NUMERO_THREADS="${2?}"
	local DIR_OUTPUT_QUALIDADE="${3?}"
	local EXTENSAO_ARQUIVO_GENOMA="${4?}"
	local MIN_COMPLETUDE="${5?}"
	local MAX_CONTAMINACAO="${6?}"
	local LISTA_GENOMAS_ALTA_QUAL="${7?}"
	
	# Arquivo de saida gerado pelo CHECKM2: quality_report.tsv

	# Limpando antigo e Criando diretorio de output final do checkm2 e limpando arquivos antigos
	if [ -d "$DIR_OUTPUT_QUALIDADE" ]; then
		rm -rf "$DIR_OUTPUT_QUALIDADE" 
	fi
	mkdir -p "$DIR_OUTPUT_QUALIDADE" \
	|| { echo "[ERRO] Nao foi possivel gerar diretorio $DIR_OUTPUT_QUALIDADE!" >> "$LOG_FILE" ; return 1 ; }
	
	# Checar variaveis de ambiente
	if [[ "$CHECKM2DB" == "" ]]; then
		echo "[ERROR] Variavel ambiente CHECKM2DB utilizada pelo checkm2 nao encontrada!" >> "$LOG_FILE"
		return 1
	fi
	
	# Flags - checkm2 predict:
	# --input <arquivo>: lista com todos os nomes de arquivo FASTA/GZ (compactado) ou o diretorio com esses arquivos (programa NAO faz busca recursiva, arquivos devem estar no 1° nivel do diretorio). NAO colocar "" para evitar que os argumentos se juntem em um so
	# --output-directory <dir>: nome do dir onde ficara o arquivo tsv com os parametros de qualidade calculados
	# --extension <.XXX>: extensao do arquivo do input, pode ser .fna, .gz, etc
	# --threads <num_threads>: numero de CPU usadas paralelamente no processamento
	# --remove_intermediates: remover arquivos intermediarios (arquivos de proteina e outros)
	# --force (nao usei): caso haja arquivos no mesmo diretorio de saida, eles sao sobrescritos (overwriting)
	
	# --- 1. DIVISAO DOS GENOMAS EM LOTES ---
	
	# Variaveis para o calculo em lotes de genomas
	local LOTE_TAMANHO=2000
	local PREFIXO_LOTE="${DIR_OUTPUT_QUALIDADE}/lote_genomas_"
	local PREFIXO_DIR_OUTPUT_LOTE="${DIR_OUTPUT_QUALIDADE}/output_lote_"
	
	# Criar arquivo com os nomes dos genomas (find retorna o caminho do arquivo - $PASTA_GENOMA/$NOME_ARQUIVO)
	local LISTA_GENOMAS="${DIR_OUTPUT_QUALIDADE}/lista_genomas.txt"
	find "$PASTA_GENOMAS" -maxdepth 1 -name "*.$EXTENSAO_ARQUIVO_GENOMA" > "$LISTA_GENOMAS" \
	|| { echo "[ERRO] Nao foi possivel encontrar os genomas em $PASTA_GENOMAS" >> "$LOG_FILE" ; return 1 ; }
	
	# LISTA_GENOMAS:
	# $PASTA_GENOMA/GCA_238293902.1.fn.gz
	# $PASTA_GENOMA/GCA_121212902.1.fn.gz
	# ...
	
	# Verificar se LISTA_GENOMAS nao esta vazio (-s verifica se existe e se nao esta vazio)
	if [[ ! -s "$LISTA_GENOMAS" ]]; then
		echo "[ERRO] Nenhum genoma .$EXTENSAO_ARQUIVO_GENOMA encontrado em $PASTA_GENOMAS" >> "$LOG_FILE"
		return 1
	fi
	
	# Separar os nomes dos genomas em lotes com split
	# split -l NUMBER (numero de linhas no output)
	# split -d (usar sufixos numericos para nomear os lotes)
	# split -a NUMBER (tamanho do sufixo. Default: 2)
	# Use: split --flags file prefix
	split -l $LOTE_TAMANHO -d -a 3 "$LISTA_GENOMAS" "$PREFIXO_LOTE" \
	|| { echo "[ERRO] Nao foi possivel separar os genomas em lotes de $LOTE_TAMANHO" >> "$LOG_FILE" ; return 1 ; }
	echo "[INFO] Separando os $(wc -l < "$LISTA_GENOMAS") genomas em lotes de $LOTE_TAMANHO unidades" >> "$LOG_FILE"
	
	# --- 2. CALCULO DA QUALIDADE COM CHECKM2 DE CADA LOTE ---
	
	echo "[INFO] Calculando a qualidade dos genomas com checkm2 versao $(checkm2 --version)" >> "$LOG_FILE"
	for lote in "$PREFIXO_LOTE"*; do # "$PREFIXO_LOTE"* expande para todos os lotes
	
		# Extrai o número do lote para organizar o output (ex: 000, 001, 002...)
		NUM_LOTE="${lote#$PREFIXO_LOTE}"
		
		DIR_OUTPUT_LOTE="${PREFIXO_DIR_OUTPUT_LOTE}${NUM_LOTE}"
		
		# Cria o diretório de output do lote atual
		mkdir -p "$DIR_OUTPUT_LOTE" \
		|| { echo "[ERRO] Nao foi possivel gerar diretorio $DIR_OUTPUT_LOTE" >> "$LOG_FILE" ; return 1 ; }
		
		# Carregar os caminhos dos genomas do lote dentro de um array
		# mapfile -t (remove o delimitador ao final da linha. Default: \n)
		mapfile -t ARRAY_GENOMAS < "$lote" \
		|| { echo "[ERRO] Nao foi mapear genomas do lote $NUM_LOTE para ARRAY_GENOMAS" >> "$LOG_FILE" ; return 1 ; }

		# Verificar se os arquivos do lote existem no dir
		for file in "${ARRAY_GENOMAS[@]}"; do
			if [[ ! -f "$file" ]]; then
				echo "[ERRO] Arquivo $file nao encontrado no diretorio $OUTPUT_DIR" >> "$LOG_FILE"
				return 1
			fi
		done
		
		# Executar o checkm2 passando os genomas como lista (pelo ARRAY_GENOMAS)
		checkm2 predict \
		--input "${ARRAY_GENOMAS[@]}" \
		--output-directory "${DIR_OUTPUT_LOTE}" \
		--extension "${EXTENSAO_ARQUIVO_GENOMA}" \
		--remove_intermediates \
		--threads "${NUMERO_THREADS}" \
			|| { echo "[ERRO] O CheckM2 falhou! Cheque o arquivo log (${DIR_OUTPUT_LOTE}/checkm2.log)" >> "$LOG_FILE" ; return 1 ; }
			
		
		# Verificar se o arquivo com a qualidade dos genomas foi gerado
		if [[ ! -f "${DIR_OUTPUT_LOTE}/quality_report.tsv" ]]; then
			echo "Arquivo de saida do checkm2 ${DIR_OUTPUT_LOTE}/quality_report.tsv para o lote $NUM_LOTE nao foi gerado" >> "$LOG_FILE"
			return 1
		else
			echo "[LOTE ${NUM_LOTE}] Calculo de qualidade completo!" >> "$LOG_FILE"
		fi
		
	done
	
	# --- 3. UNINDO OS RESULTADOS DE CADA LOTE ---

	# Junta todos os quality_report.tsv (mantendo o header só do primeiro)
	# 1° arquivo: FNR==NR é verdadeiro
	# 2° ou N° arquivo: FNR==NR é falso, logo FNR>1 se torna verdadeiro (pula o HEADER)
	awk 'FNR==NR || FNR>1' 	"${PREFIXO_DIR_OUTPUT_LOTE}"*/quality_report.tsv > "${DIR_OUTPUT_QUALIDADE}/quality_report.tsv" \
		|| { echo "[ERRO] Nao foi possivel unir os resultados dos lotes" >> "$LOG_FILE" ; return 1 ; }

	# Limpando arquivos e diretorios de todos os lotes de uma vez
	rm -rf "${PREFIXO_DIR_OUTPUT_LOTE}"* "${PREFIXO_LOTE}"* \
		|| { echo "[ERRO] Nao foi possivel remover arquivos dos lotes" >> "$LOG_FILE" ; return 1 ; }
	
	echo "[SUCESSO] Resultados do checkm2 salvos em $DIR_OUTPUT_QUALIDADE" >> "$LOG_FILE"
	
	local OUTPUT_CHECKM2="${DIR_OUTPUT_QUALIDADE}/quality_report.tsv"
	# Colunas: Name    Completeness    Contamination   Completeness_Model_Used Translation_Table_Used  Coding_Density    Contig_N50      Average_Gene_Length     Genome_Size     GC_Content      Total_Coding_Sequences    Total_Contigs   Max_Contig_Length       Additional_Notes
	
	# --- 4. PASSANDO GENOMAS SELECIONADOS PARA LISTA ---
	# Completude - penultima col (NF-1)
	# Contaminacao - ultima col (NF)
	awk -F'\t' -v min_completude="$MIN_COMPLETUDE" \
	-v max_contaminacao="$MAX_CONTAMINACAO" \
	-v lista_genomas="$LISTA_GENOMAS_ALTA_QUAL" '
	NR > 1 {
		arq_genoma = $1
		completude = $2
		contaminacao = $3
		
		# Extrair id do genoma
		if (match(arq_genoma, /GC[AF]_[0-9]+\.[0-9]+/)) {
			id_genoma = substr(arq_genoma, RSTART, RLENGTH)
		}
		
		# Imprimir o id do genoma na lista, caso esteja dentro dos criterios
		if (completude >= min_completude && contaminacao <= max_contaminacao) {
			print id_genoma > lista_genomas
		}
	} ' "$OUTPUT_CHECKM2" \
		|| { echo "[ERRO] Comando awk falhou!" >> "$LOG_FILE" ; return 1 ; }
}