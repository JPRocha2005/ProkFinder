# Funcao para buscar a classificacao taxonomica do genoma (pelo codigo de acesso) na base de dados taxonomicos do GTDB

 # Uso: create_taxonomic_file <gtdb_link> <archaea_file> <bacteria_file> <genome_curated_metadata>
# <dir_output_tax> <output_genomes_tax> <output_list_non_classify_genomes>
create_taxonomic_file () {
	local GTDB_DATABASE_LINK="${1?}"
	local ARCHAEA_FILE="${2?}"
	local BACTERIA_FILE="${3?}"
	local CURATED_GENOMES_METADATA="${4?}"
	local DIR_TAXONOMY="${5?}"
	local OUTPUT_CURATED_GENOMES_TAXONOMY="${6?}"
	local OUTPUT_NO_TAX_GENOMES_LIST="${7?}"
	
	# Limpar o link para remover barras duplas (//)
	local GTDB_DATABASE_LINK="${GTDB_DATABASE_LINK%/}"
	
	# Monta as URLs completas para o download
	
	local ARCHAEA_URL="${GTDB_DATABASE_LINK}/$(basename $ARCHAEA_FILE)"
	local BACTERIA_URL="${GTDB_DATABASE_LINK}/$(basename $BACTERIA_FILE)"
	local PROKARYOTE_TAXONOMY="gtdb_prokaryote_taxonomy.tsv"
	
	# Limpando antigo e criando diretorio de output final da taxonomia
	if [ -d "$DIR_TAXONOMY" ]; then
		rm -rf "$DIR_TAXONOMY" 
	fi
	mkdir -p "$DIR_TAXONOMY" \
	|| { echo "[ERRO] Nao foi possivel gerar diretorio $DIR_TAXONOMY!" >> "$LOG_FILE" ; return 1 ; }

	# 1 - Recuperar os arquivos de taxonomia do GTDB
	
	echo "Baixando arquivos de taxonomia de arqueia e bacteria do GTDB" >> "$LOG_FILE"
	# wget: -q para modo silencioso (opcional), -O nome do output
	if ! wget -q "$ARCHAEA_URL" -O "$ARCHAEA_FILE" ; then
		echo "[ERROR] Falha ao baixar o arquivo de Archaea ($ARCHAEA_FILE)." >> "$LOG_FILE"
		return 1
	else
		echo "[SUCESSO] Arquivo de taxonomia do GTDB para Archaea baixado: $ARCHAEA_FILE" >> "$LOG_FILE"
	fi
	if ! wget -q "$BACTERIA_URL" -O "$BACTERIA_FILE"; then
		echo "[ERROR] Falha ao baixar o arquivo de Bacteria ($BACTERIA_FILE)." >> "$LOG_FILE"
		rm -f "$ARCHAEA_FILE" # remove o outro arquivo
		return 1
	else
		echo "[SUCESSO] Arquivo de taxonomia do GTDB para Bacteria baixado: $BACTERIA_FILE" >> "$LOG_FILE"
	fi
	
	# 2- Descompactar e concatenar o conteudo dos arquivos de taxonomia usando zcat
	zcat "$ARCHAEA_FILE" "$BACTERIA_FILE" > "$PROKARYOTE_TAXONOMY" # Sem HEADER
	
	# 3 - Formatar o arquivo de taxonomia de procariotos
	
	### AVISO: Manter os genomas tanto do GenBank quanto do RefSeq - caso os numeros no ID sejam identicos, serao considerados como genomas com a mesma taxonomia ###
	
	# Prefixos dos genomas no taxonomia do GTDB
	# GB_GCA_047973225.1 - Genoma da base de dados do GenBank
	# RS_GCF_049330835.1 - Genoma da base de dados do RefSeq
	sed -i 's/^RS_GCF/GCF/' "$PROKARYOTE_TAXONOMY"
	sed -i 's/^GB_GCA/GCA/' "$PROKARYOTE_TAXONOMY"
	
	# 4 - Buscar pela taxonomia dos genomas no arquivo do GTDB, pelo codigo de acesso (1° coluna em ambos arquivos)
	
	# Inserindo o header nos metadados de saida
	echo -ne "Assembly Accession\tClassification\n" > "$OUTPUT_CURATED_GENOMES_TAXONOMY"
	
	# Awk faz o mapeamento Taxonomia_GTDB <-> Genoma_Metadados a partir dos numeros do id de acesso e nao do id propriamente dito (GCA_... ou GCF_...)
	
	awk -F'\t' -v OFS="\t" -v out_taxonomy="$OUTPUT_CURATED_GENOMES_TAXONOMY" \
	-v out_no_taxonomy_genomes="$OUTPUT_NO_TAX_GENOMES_LIST" '
		
		NR == FNR { # le o 1° arquivo
			
			# 1. Carregando a taxonomia e o acessos dos genoma (indice) numa tabela hash
			
			genome_acc = $1
			gtdb_taxonomy = $2
			
			# Obtendo apenas o numero do id (removendo o prefixo GCA_ ou GCF_)
			if (match(genome_acc, /[0-9.]+/)) { genome_id = substr(genome_acc, RSTART, RLENGTH) } 
			
			taxonomy_vector[genome_id] = gtdb_taxonomy
			next # proxima linha
		}
		
		FNR > 1 { # pula o HEADER do 2° arquivo
		
			metadata_genome_acc = $1

			# Obtendo apenas o numero do id (removendo o prefixo GCA_ ou GCF_)
			if (match(metadata_genome_acc, /[0-9.]+/)) { metadata_genome_id = substr(metadata_genome_acc, RSTART, RLENGTH) } 

			# 2. Buscando pelos codigos de acesso dos genomas na taxonomia do GTDB
			if (metadata_genome_id in taxonomy_vector) {
				print metadata_genome_acc,taxonomy_vector[metadata_genome_id] > out_taxonomy
			}
			
			# Se nao houver correspondencia com a lista do GTDB, acesso do genoma é guardado na lista
			else {
				print metadata_genome_acc > out_no_taxonomy_genomes
			}
		}
	
	' "$PROKARYOTE_TAXONOMY" "$CURATED_GENOMES_METADATA"
	
	# 5 - Removendo arquivos
	rm -f "$ARCHAEA_FILE" "$BACTERIA_FILE" "$PROKARYOTE_TAXONOMY"
}

