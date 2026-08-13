# Funcao para fazer a desreplicacao dos genomas utilizando o skDER

# Uso: desreplicacao_no_dir_taxonomia <tabela_dir_folha> <max_memoria> <num_cpus> <extensao_genoma> <output_tabela_dir_folha_rep> <output_lista_genomas_rep> <programa_filtragem_mge>
desreplicacao_genomas () {
	local TABELA_DIR_FOLHA="${1?}"
	local MAX_MEMORY="${2?}"
	local NUM_CPUS="${3?}"
	local EXTENSAO_GENOMA="${4?}"
	local TABELA_DIRS_FOLHA_REPRESENTATIVOS="${5?}"
	local LISTA_GENOMAS_REPRESENTATIVOS="${6?}"
	local PROGRAMA_FILTRAGEM_MGE="${7?}"

	# Arquivos gerados pelo skder
	local CAMINHOS_GENOMAS_ORIGINAIS="All_Genomes_Listing.txt"
	local CAMINHO_GENOMAS_COM_MGE_FILTRADO="All_Genomes_Listing_mgecut_Processed.txt" # nao usarei
	local DIR_GENOMAS_COM_MGE_FILTRADO="mgecut_processed_genomes" # nao usarei
	local DIR_GENOMAS_ORIGINAIS_REPRESENTATIVOS="Dereplicated_Representative_Genomes" # tem o symlink, caso use a flag
	local CAMINHOS_GENOMAS_ORIGINAIS_REPRESENTATIVOS="skDER_Results.txt"
	
	# [IMPORTANTE] skDER nao gera um diretorio separado com todos os resultados, os resultados do skDER sao gerados dentro de cada um dos diretorios-folha dentro da estrutura de dirs de ranks taxonomicos
	
	# Criando arquivo de output
	> "$TABELA_DIRS_FOLHA_REPRESENTATIVOS"
	> "$LISTA_GENOMAS_REPRESENTATIVOS"
  
	# 1. Rodar skder em cada dir-folha
	while read -r DIR_FOLHA NUMERO_GENOMAS; do
		
		# 1.1 Gerando diretorios dentro do dir-folha para organizacao
		local DIR_GENOMAS_REPRESENTATIVOS="${DIR_FOLHA}/REPRESENTATIVE-GENOMES"
		limpar_diretorio "$DIR_GENOMAS_REPRESENTATIVOS" || return 1
		
		# 1.2 Avaliando se ha genomas no dir-folha
		mapfile -t ARRAY_GENOMAS < <(find "$DIR_FOLHA" -maxdepth 1 -type f -name "*.$EXTENSAO_GENOMA")
		if [ "${#ARRAY_GENOMAS[@]}" -eq 0 ]; then
			echo "[ERRO] Nenhum genoma com extensao $EXTENSAO_GENOMA encontrado em $DIR_FOLHA" >> "$LOG_FILE"
			return 1
		fi

		# 1.3 Fazendo a desreplicacao dos genomas no dir-folha, caso haja mais de um genoma no dir
		if [ "$NUMERO_GENOMAS" -gt 1 ]; then 
			local DIR_RESULTADOS_SKDER="${DIR_GENOMAS_REPRESENTATIVOS}/SKDER-RESULTS"
			local ARQ_CAMINHOS_GENOMAS_SKDER="${DIR_RESULTADOS_SKDER}/${CAMINHOS_GENOMAS_ORIGINAIS_REPRESENTATIVOS}" # arquivo com os caminhos
			
			# 1.3.1 Checar o programa de filtragem de mge
			if [ "$PROGRAMA_FILTRAGEM_MGE" == "genomad" ]; then
				preparar_banco_genomad # preenche FLAG_GENOMAD
			elif [ "$PROGRAMA_FILTRAGEM_MGE" == "phispy" ]; then
				FLAG_GENOMAD=""
			else
				echo "[ERRO] Programa de filtragem do MGE nao reconhecido: $PROGRAMA_FILTRAGEM_MGE" >> "$LOG_FILE"
				echo "[ERRO] So sao aceitos genomad ou phispy no argumento" >> "$LOG_FILE"
				return 1
			fi
			
			# 1.3.2 Executar skder
			skder --genomes "${ARRAY_GENOMAS[@]}" \
			--output-directory "$DIR_RESULTADOS_SKDER" \
			--dereplication-mode "greedy" \
			--symlink \
			--max-memory "$MAX_MEMORY" \
			--threads "$NUM_CPUS" \
			$FLAG_GENOMAD \
			--filter-mge \
				|| { echo "[ERRO] Execucao do skder falhou!" >> "$LOG_FILE"; return 1 ; }
			
			# 1.3.3 Buscar os genomas representativos que o skder selecionou (dentro de skder-results.txt)
			mapfile -t ARRAY_GENOMAS_REPRESENTATIVOS < "$ARQ_CAMINHOS_GENOMAS_SKDER"
			if [ "${#ARRAY_GENOMAS_REPRESENTATIVOS[@]}" -eq 0 ]; then
				echo "[ERRO] Nenhum genoma representativo encontrado em $ARQ_CAMINHOS_GENOMAS_SKDER" >> "$LOG_FILE"
				return 1
			fi

			# 1.3.4 Movendo genomas representativos para novo diretorio (ANTES de gravar os novos caminhos). Deixando dir com genomas redundantes
			mv "${ARRAY_GENOMAS_REPRESENTATIVOS[@]}" "$DIR_GENOMAS_REPRESENTATIVOS" \
				|| { echo "[ERRO] Nao foi possivel mover genomas para diretorio $DIR_GENOMAS_REPRESENTATIVOS" >> "$LOG_FILE" ; return 1 ; }
			rm -f "$ARQ_CAMINHOS_GENOMAS_SKDER" # removendo skDER.results.txt com caminhos antigos			
				
			# 1.3.5 Gravando na lista/tabela os novos caminhos dos genomas representativos
			local NOME_GENOMA CAMINHO_FINAL CAMINHO_SYMLINK
			for CAMINHO_ANTIGO in "${ARRAY_GENOMAS_REPRESENTATIVOS[@]}"; do
				NOME_GENOMA=$(basename "$CAMINHO_ANTIGO")
				CAMINHO_FINAL="${DIR_GENOMAS_REPRESENTATIVOS}/${NOME_GENOMA}"

				echo "$CAMINHO_FINAL" >> "$LISTA_GENOMAS_REPRESENTATIVOS"
				echo -e "${CAMINHO_FINAL}\t${NUMERO_GENOMAS}" >> "$TABELA_DIRS_FOLHA_REPRESENTATIVOS"

				# 1.3.5a Atualizar o arquivo do skDER com os novos caminhos dos genomas representativos
				echo "$CAMINHO_FINAL" >> "$ARQ_CAMINHOS_GENOMAS_SKDER"

				# 1.3.5b Corrigir symlink quebrado dentro de SKDER-RESULTS/Dereplicated_Representative_Genomes
				CAMINHO_SYMLINK="${DIR_RESULTADOS_SKDER}/${DIR_GENOMAS_ORIGINAIS_REPRESENTATIVOS}/${NOME_GENOMA}"
				if [ -L "$CAMINHO_SYMLINK" ]; then
					ln -sfn "$CAMINHO_FINAL" "$CAMINHO_SYMLINK" \
						|| { echo "[ERRO] Falha ao re-apontar symlink $CAMINHO_SYMLINK" >> "$LOG_FILE" ; return 1 ; }
				else
					echo "[AVISO] Symlink esperado nao encontrado em $CAMINHO_SYMLINK" >> "$LOG_FILE"
				fi

			done
			
			echo "[INFO] Desreplicacao dos $NUMERO_GENOMAS genomas da especie $(basename $DIR_FOLHA) concluida" >> "$LOG_FILE"
			
		# 1.4 Caso haja um unico genoma, apenas mover o genoma representativo
		else
			# 1.4.1 Movendo genoma representativo para novo diretorio
			CAMINHO_GENOMA_UNICO="${ARRAY_GENOMAS[0]}" # variavel com o caminho
			mv "$CAMINHO_GENOMA_UNICO" "$DIR_GENOMAS_REPRESENTATIVOS" \
				|| { echo "[ERRO] Nao foi possivel mover genoma para diretorio $DIR_GENOMAS_REPRESENTATIVOS" >> "$LOG_FILE" ; return 1 ; }
			
			# 1.4.2 Gravando na lista/tabela os novos caminhos dos genomas representativos
			local NOME_GENOMA_UNICO NOVO_CAMINHO_GENOMA_UNICO
			NOME_GENOMA_UNICO="$(basename "$CAMINHO_GENOMA_UNICO")"
			NOVO_CAMINHO_GENOMA_UNICO="${DIR_GENOMAS_REPRESENTATIVOS}/${NOME_GENOMA_UNICO}"
			echo "$NOVO_CAMINHO_GENOMA_UNICO" >> "$LISTA_GENOMAS_REPRESENTATIVOS"
			echo -e "${NOVO_CAMINHO_GENOMA_UNICO}\t1" >> "$TABELA_DIRS_FOLHA_REPRESENTATIVOS"
			
			echo "[INFO] Genomas da especie $(basename $DIR_FOLHA) nao precisou de desreplicacao, unico genoma na especie" >> "$LOG_FILE"
		fi
		
	done < "$TABELA_DIR_FOLHA"
	
	echo "[INFO] Desreplicacao dos genomas concluida!" >> "$LOG_FILE"
}

# Funcao para preparar o database do genomad, caso ele seja escolhido como programa para realizar a filtragem dos mge (elementos geneticos moveis)
preparacao_genomad_database () {
	# Variaveis locais
	local GENOMAD_DB_DIR="$HOME/diretorio_projeto/db/genomad"
	local GENOMAD_VERSION=$(genomad --version | awk '{print $NF}')
	local GENOMAD_DB_PATH="${GENOMAD_DB_DIR}/genomad_db_v${GENOMAD_VERSION}"

	if [ ! -d "$GENOMAD_DB_PATH" ]; then
		mkdir -p "$GENOMAD_DB_PATH"

		echo "[INFO] Banco compativel com geNomad v${GENOMAD_VERSION} nao encontrado. Baixando em ${GENOMAD_DB_PATH} ..." >> "$LOG_FILE"
		genomad download-database "$GENOMAD_DB_PATH" \
			|| { echo "[ERRO] Download do banco de dados do geNomad falhou!" >> "$LOG_FILE" ; return 1 ; }
		echo "[INFO] Download completo!" >> "$LOG_FILE"
	else
		echo "[INFO] Banco geNomad ja existente em ${GENOMAD_DB_PATH}. Pulando download." >> "$LOG_FILE"
	fi

	FLAG_GENOMAD="--genomad-db ${GENOMAD_DB_PATH}/genomad_db"

}

# 9. Inconsistência estrutural entre os dois branches: no branch de múltiplos genomas, os representativos ficam dentro de DIR_GENOMAS_REPRESENTATIVOS/SKDER-RESULTS/ (assumindo que o skder usa --symlink para colocar os genomas ali); no branch de genoma único, o genoma vai direto para DIR_GENOMAS_REPRESENTATIVOS/ (sem subpasta). Não é um bug de sintaxe, mas gera uma estrutura de diretórios inconsistente entre os dois casos — pode complicar quem for consumir esse diretório depois. Vale considerar padronizar.

# └──╼ $ skder -h
        # skDER: efficient & high-resolution dereplication of microbial genomes to select
                   # representative genomes.

        # skDER will perform dereplication of genomes using skani average nucleotide identity
        # (ANI) and aligned fraction (AF) estimates and either a dynamic programming or
        # greedy-based based approach. It assesses such pairwise ANI & AF estimates to determine
        # whether two genomes are similar to each other and then chooses which genome is better
        # suited to serve as a representative based on assembly N50 (favoring the more contiguous
        # assembly) and connectedness (favoring genomes deemed similar to a greater number of
        # alternate genomes).

        # Note, if --filter-mge is requested, the original paths to genomes are reported but
        # the statistics reported in the clustering reports (e.g. ANI, AF) will all be based
        # on processed (MGE filtered) genomes. 
		
		# Importantly, computation of N50 is performed
        # before MGE filtering to not penalize genomes of high quality that simply have many
        # MGEs and enable them to still be selected as representatives.

        # If you use skDER for your research, please kindly cite both:
        # Fast and robust metagenomic sequence comparison through sparse chaining with skani.
        # Nature Methods. Shaw and Yu, 2023.
        # and
        # skDER & CiDDER: two scalable approaches for microbial dereplication. Microbial
        # Genomics. Salamzade, Kottapalli, and Kalan, 2025.


# options:
  # -h, --help            show this help message and exit
  # -g GENOMES [GENOMES ...], --genomes GENOMES [GENOMES ...]
                        # Genome assembly file paths or paths to containing
                        # directories. Files should be in FASTA format and can be gzipped
                        # (accepted suffices are: *.fasta,
                        # *.fa, *.fas, or *.fna) [Optional].
  # -t TAXA_NAME, --taxa-name TAXA_NAME
                        # Genus or species identifier from GTDB for which to
                        # download genomes for and include in
                        # dereplication analysis [Optional].
  # -o OUTPUT_DIRECTORY, --output-directory OUTPUT_DIRECTORY
                        # Output directory.
  # -d DEREPLICATION_MODE, --dereplication-mode DEREPLICATION_MODE
                        # Whether to use a "dynamic" (more concise), "greedy" (more
                        # comprehensive), or "low_mem_greedy" (currently
                        # experimental) approach to selecting representative genomes.
                        # [Default is "greedy"]
  # -i PERCENT_IDENTITY_CUTOFF, --percent-identity-cutoff PERCENT_IDENTITY_CUTOFF
                        # ANI cutoff for dereplication [Default is 99.5].
  # -f ALIGNED_FRACTION_CUTOFF, --aligned-fraction-cutoff ALIGNED_FRACTION_CUTOFF
                        # Aligned cutoff threshold for dereplication - only needed by
                        # one genome [Default is 50.0].
  # -a MAX_AF_DISTANCE_CUTOFF, --max-af-distance-cutoff MAX_AF_DISTANCE_CUTOFF
                        # Maximum difference for aligned fraction between a pair to
                        # automatically disqualify the genome with a higher
                        # AF from being a representative [Default is 10.0].
  # -tc, --test-cutoffs   Assess clustering using various pre-selected cutoffs.
  # -p SKANI_TRIANGLE_PARAMETERS, --skani-triangle-parameters SKANI_TRIANGLE_PARAMETERS
                        # Options for skani triangle. Note ANI and AF cutoffs
                        # are specified separately and the -E parameter is always
                        # requested. [Default is "-s X", where X is
                        # 10 below the ANI cutoff].
  # -s, --sanity-check    Confirm each FASTA file provided or downloaded is actually
                        # a FASTA file. Makes it slower, but generally
                        # good practice.
  # -fm, --filter-mge     Filter predicted MGE coordinates along genomes before
                        # dereplication assessment but after N50
                        # computation.
  # -fms FILTER_MGE_SKIP_REGIONS, --filter-mge-skip-regions FILTER_MGE_SKIP_REGIONS
                        # Path to tab-delimited file defining genomic regions to
                        # skip during MGE filtering (genome file name, scaffold
                        # name, start, end). Enables MGE filtering using
                        # user-provided coordinates instead of PhiSpy/geNomad
                        # prediction (experimental).
  # -gd GENOMAD_DATABASE, --genomad-database GENOMAD_DATABASE
                        # If filter-mge is specified, it will by default use PhiSpy;
                        # however, if a database directory for
                        # geNomad is provided - it will use that instead
                        # to predict MGEs.
  # -n, --determine-clusters
                        # Perform secondary clustering to assign non-representative
                        # genomes to their closest representative genomes.
  # -mn MINIMAL_N50, --minimal_n50 MINIMAL_N50
                        # Minimal N50 of genomes to be included in dereplication
                        # [Default is 0].
  # -l, --symlink         Symlink representative genomes in results subdirectory
                        # instead of performing a copy of the files.
  # -r GTDB_RELEASE, --gtdb-release GTDB_RELEASE
                        # Which GTDB release to use if -t argument issued [Default is R232].
  # -auto, --automate     Automatically skip warnings and download genomes from NCBI if -t
                        # argument issued. Automatation off by default to prevent
                        # unexpected downloading of large genomes [Default
                        # is False].
  # -mm MAX_MEMORY, --max-memory MAX_MEMORY
                        # Max memory in Gigabytes [Default is 0 = unlimited].
  # -c THREADS, --threads THREADS
                        # Number of threads/processes to use [Default is 1].
  # -v, --version         Report version of skDER
  
  	
	# Arquivos de output do skder:
	# All_Genomes_Listing.txt
	# All_Genomes_Listing_mgecut_Processed.txt
	# mgecut_processed_genomes
	# mgecut_tmp
	# COMPLETED.txt
	# Command_Issued.txt
	# Concatenated_N50.txt
	# Dereplicated_Representative_Genomes
	# Genome_Information_for_Greedy_Clustering.sorted.txt
	# Genome_Information_for_Greedy_Clustering.txt
	# Progress.log
	# Skani_Triangle_Edge_Output.txt
	# skDER_Results.txt