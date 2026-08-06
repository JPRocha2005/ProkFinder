# Funcao para gerar o PBS separadamente do resto da pipeline (apenas se a execucao for no cluster)
gerar_pbs_etapa_9() {
    local pbs_file="$1" job_name="$2" ncpus="$3" mem="$4" queue="$5" walltime="$6" \
          lista_genomas="$7" extensao="$8" cpus_pplacer="$9" dir_output="${10}"
		  
	local CLASSIFY_GENOMES_MODULE="$(realpath "../${DIR_MODULOS}/9_Find-Missing-Taxonomy.sh")"
	local MAIN_MODULE="$(realpath "../${DIR_MODULOS}/Main-Function_2.sh")"
	local MODULO_GTDBTK="gtdbtk/2.7.2"

    cat > "$pbs_file" <<EOF
#!/bin/bash
#PBS -N ${job_name}
#PBS -l select=1:ncpus=${ncpus}:mem=${mem}gb
#PBS -q ${queue}
#PBS -l walltime=${walltime}
#PBS -o ${dir_output}/${job_name}.out
#PBS -e ${dir_output}/${job_name}.err

cd "\${PBS_O_WORKDIR}"

# Carregando modulo do gtdbtk
module load ${MODULO_GTDBTK}

# Carregando funcao classify_genomes e main_function
source "${CLASSIFY_GENOMES_MODULE}" 
source "${MAIN_MODULE}"

# Carregando variaveis necessarias para execucao
LOG_FILE="$LOG_FILE"
A_DIR_GENOMAS="$A_DIR_GENOMAS"
F_EXTENSAO_ARQUIVO_GENOMA="$F_EXTENSAO_ARQUIVO_GENOMA"

# Uso: classify_genomes <list_non_classified_genomes> <genomes_extension> <number_of_cpus> <number_of_cpus_for_pplacer> <output_dir_tax_classication>
classify_genomes "${lista_genomas}" "${extensao}" "${ncpus}" "${cpus_pplacer}" "${dir_output}"
exit \$?
EOF
}

# Funcao para submissao e aguardo do PBS pai, enquanto o PBS filho é executado
submeter_e_aguardar() {
    local pbs_file="$1" job_name="$2" intervalo=5
    local job_id estado exit_status

    job_id=$(qsub "$pbs_file" && rm -f "$pbs_file") || { echo "Falha ao submeter ${job_name}" >> "$LOG_FILE"; return 1 ; }
    echo "Job ${job_name} submetido (ID: ${job_id})" >> "$LOG_FILE"

	# Loop para ir checando se o job finalizou a cada ${intervalo} segundos
    while true; do
        estado=$(qstat -f "$job_id" 2>/dev/null | awk -F'= ' '/job_state/{print $2}' | tr -d ' ')
        [[ -z "$estado" ]] && estado=$(qstat -xf "$job_id" 2>/dev/null | awk -F'= ' '/job_state/{print $2}' | tr -d ' ')
        [[ "$estado" == "F" ]] && break
        sleep "$intervalo"
    done

    exit_status=$(qstat -xf "$job_id" 2>/dev/null | awk -F'= ' '/Exit_status/{print $2}' | tr -d ' ')

	# Verificando se o JOB finalizou com sucesso
    if [[ "$exit_status" -eq 0 ]]; then
        echo "Job ${job_name} (${job_id}) OK." >> "$LOG_FILE"
        return 0
    else
        echo "Job ${job_name} (${job_id}) falhou (exit_status=${exit_status})." >> "$LOG_FILE"
        return 1
    fi
}


# Funcao para mesclar um arquivo de summary especifico (bac120 ou ar53) gerado em cada lote do gtdbtk
# em um unico arquivo consolidado, mantendo apenas um cabecalho no arquivo final

# Chamando a funcao
# mesclar_arquivo_summary_lotes <dir_resultados_classificacao> <nome_arquivo_summary> <arquivo_summary_mesclado>
mesclar_arquivo_summary_lotes () {
	local DIR_RESULTADOS_CLASSIFICAO="${1?}"
	local NOME_ARQUIVO_SUMMARY="${2?}"
	local ARQUIVO_SUMMARY_MESCLADO="${3?}"

	# Encontrando todos os arquivos de summary com esse nome dentro dos subdiretorios de lote (lote_000, lote_001...)
	# 2>/dev/null para nao gerar erro caso nenhum lote tenha gerado esse arquivo (ex: dataset sem arqueias)
	local ARQUIVOS_SUMMARY_LOTES=$(find "$DIR_RESULTADOS_CLASSIFICAO" -mindepth 2 -maxdepth 2 -type f -name "$NOME_ARQUIVO_SUMMARY" 2>/dev/null | sort)

	# Se nenhum lote gerou esse arquivo, nao ha nada para mesclar (ex: dataset sem genomas do dominio Archaea)
	if [ -z "$ARQUIVOS_SUMMARY_LOTES" ]; then
		echo "[INFO] Nenhum arquivo $NOME_ARQUIVO_SUMMARY encontrado nos lotes. Etapa de mesclagem ignorada para esse arquivo." >> "$LOG_FILE"
		return 0
	fi

	# Pegando o cabecalho apenas do primeiro arquivo encontrado
	local PRIMEIRO_ARQUIVO=$(echo "$ARQUIVOS_SUMMARY_LOTES" | head -n 1)
	head -n 1 "$PRIMEIRO_ARQUIVO" > "$ARQUIVO_SUMMARY_MESCLADO"

	# Concatenando as linhas de dados (sem o cabecalho) de cada arquivo de summary encontrado
	local ARQUIVO_ATUAL
	for ARQUIVO_ATUAL in $ARQUIVOS_SUMMARY_LOTES; do
		tail -n +2 "$ARQUIVO_ATUAL" >> "$ARQUIVO_SUMMARY_MESCLADO"
	done

	echo "Arquivo $NOME_ARQUIVO_SUMMARY mesclado de $(echo "$ARQUIVOS_SUMMARY_LOTES" | wc -l) lote(s) e salvo em: $ARQUIVO_SUMMARY_MESCLADO" >> "$LOG_FILE"
}

# Funcao para mesclar os resultados de classificacao taxonomica (gtdbtk.bac120.summary.tsv e gtdbtk.ar53.summary.tsv)
# de todos os lotes processados pelo gtdbtk classify_wf em arquivos unicos e consolidados

# Chamando a funcao
# mesclar_resultados_gtdbtk_lotes <dir_resultados_classificacao>
mesclar_resultados_gtdbtk_lotes () {
	local DIR_RESULTADOS_CLASSIFICAO="${1?}"

	# Mesclando o summary de bacterias (caso exista em algum lote)
	mesclar_arquivo_summary_lotes \
	"$DIR_RESULTADOS_CLASSIFICAO" \
	"gtdbtk.bac120.summary.tsv" \
	"$DIR_RESULTADOS_CLASSIFICAO/gtdbtk.bac120.summary.tsv"

	# Mesclando o summary de arqueias (caso exista em algum lote)
	mesclar_arquivo_summary_lotes \
	"$DIR_RESULTADOS_CLASSIFICAO" \
	"gtdbtk.ar53.summary.tsv" \
	"$DIR_RESULTADOS_CLASSIFICAO/gtdbtk.ar53.summary.tsv"
}

# Funcao para classificar os genomas que nao tem uma taxonomia definida no GTDB utilizando o programa GTDB-TK (GTDB Toolkit)

# Chamando a funcao
# classify_genomes <list_non_classified_genomes> <genomes_extension> <number_of_cpus> <number_of_cpus_for_pplacer> <output_dir_tax_classication>
classify_genomes () {
	local LISTA_GENOMAS_NAO_CLASSIFICADOS="${1?}"
	local EXTENSAO_GENOMAS="${2?}"
	local NUMERO_CPUS="${3?}"
	local PPLACER_NUMERO_CPUS="${4?}" # metade das cpus
	local DIR_RESULTADOS_CLASSIFICAO="${5?}"
	
	limpar_diretorio "$DIR_RESULTADOS_CLASSIFICAO"
		
	# Funcionamento do gtdbtk classify_wf:
	# Le o arquivo dos genomas, faz o calculo do ANI, a identificacao dos genes marcadores, o alinhamento multiplo com outros marcadores do GTDB e, a partir desse MSA, ele posiciona o genoma na arvore filogenetica ja previamente montada (na variavel ambiente: GTDBTK_DATA_PATH). Ou seja, o comando classify_wf nao constroi a arvore do zero, mas sim o posicionamento filogenétio do genoma para encontrar sua taxonomia

	# Para criar a arvore filogenetica do zero, deve-se se usar o outro comando:
	# gtdbtk de_novo_wf

	# FLAGS:
	# --batchfile: arquivo separado por tabs com o caminho para o arquivo dos genomas na 1° coluna e o ID dos genomas na 2°
	# --genome_dir (opcao ao --batchfile): diretorio contendo os genomas 
	# --out_dir: diretorio para colocar os resultados da classificacao taxonomica
	# --cpus: numero de cpus que é utilizado pelo o programa como um todos
	# --pplacer_cpus: numero de cpus que é utilizado apenas pelo programa pplacer, o qual posiciona o genoma na arvore
	# --extension: extensao do arquivo com os genomas (fna - FASTA / gz - compactado)
	# --full_tree (nao utilizada): nao quebra a arvore filogenetica bacteria, utiliza-a inteira. Essa é a abordagem do GTDB-Tk V1 e necessita de 320 GB de RAM para carregar a arvore

	# Em datasets muito grandes (5000+ genomas), a etapa de calculo de ANI com skani do gtdbtk classify_wf
	# pode falhar sem uma causa clara (skani returned a non-zero exit code). Para contornar isso, a lista de
	# genomas nao classificados e dividida em lotes menores, e cada lote e classificado separadamente,
	# em um subdiretorio proprio dentro de $DIR_RESULTADOS_CLASSIFICAO.
	local TAMANHO_LOTE=500

	# Diretorio temporario para guardar os arquivos de cada lote (um arquivo por lote, com os IDs dos genomas)
	local DIR_LOTES_TEMP=$(mktemp -d)

	# Dividindo a lista de genomas nao classificados em arquivos de no maximo $TAMANHO_LOTE linhas cada
	# prefixo "lote_" + sufixo numerico (000, 001, 002...)
	split -l "$TAMANHO_LOTE" -d -a 3 "$LISTA_GENOMAS_NAO_CLASSIFICADOS" "$DIR_LOTES_TEMP/lote_"

	# Iterando sobre cada lote gerado e rodando o gtdbtk separadamente para cada um
	local ARQUIVO_LOTE
	for ARQUIVO_LOTE in "$DIR_LOTES_TEMP"/lote_*; do

		local NOME_LOTE=$(basename "$ARQUIVO_LOTE")
		local DIR_RESULTADOS_LOTE="$DIR_RESULTADOS_CLASSIFICAO/$NOME_LOTE"

		# Criando tabela de genomas do lote com caminho na 1° coluna e ID na 2° coluna
		local CAMINHOS_GENOMAS_TEMP=$(mktemp)
		local TABELA_GENOMAS_TEMP=$(mktemp)
		# inserir caminhos dos genomas no arquivo (funcao: encontrar_caminho_genoma <output> <filtro_genomas>
		encontrar_caminho_genoma "$CAMINHOS_GENOMAS_TEMP" "$ARQUIVO_LOTE" || return 1
		# inserir id dos genomas na segunda coluna
		paste "$CAMINHOS_GENOMAS_TEMP" "$ARQUIVO_LOTE" > "$TABELA_GENOMAS_TEMP"

		# Executando comando do gtdbtk para classificacao taxonomica do lote
		gtdbtk classify_wf \
		--batchfile "$TABELA_GENOMAS_TEMP" \
		--cpus "$NUMERO_CPUS" \
		--pplacer_cpus "$PPLACER_NUMERO_CPUS" \
		--extension "$EXTENSAO_GENOMAS" \
		--out_dir "$DIR_RESULTADOS_LOTE"

		# Verificando status de saida do gtdbtk para o lote
		if [ "$?" -eq 0 ]; then
			echo "Classificacao taxonomica do $NOME_LOTE obtida e salva no dir: $DIR_RESULTADOS_LOTE" >> "$LOG_FILE"
		else
			echo "[ERRO] O gtdbtk falhou no $NOME_LOTE! Nao foi possivel obter a classificacao taxonomica." >> "$LOG_FILE"
			rm -f "$CAMINHOS_GENOMAS_TEMP" "$TABELA_GENOMAS_TEMP"
			rm -rf "$DIR_LOTES_TEMP"
			return 1
		fi

		# Removendo arquivos temporarios do lote
		rm -f "$CAMINHOS_GENOMAS_TEMP" "$TABELA_GENOMAS_TEMP"
	done

	# Removendo diretorio temporario dos lotes
	rm -rf "$DIR_LOTES_TEMP"

	# Mesclando os arquivos de summary (bac120 e ar53) de todos os lotes em arquivos unicos
	mesclar_resultados_gtdbtk_lotes "$DIR_RESULTADOS_CLASSIFICAO"
}

# Funcao para atualizar o arquivo de taxonomia
# Uso: update_taxonomy_file <taxonomy_file> <new_taxonomy_file> <gtdbtk_results_dir:OPCIONAL>

update_taxonomy_file () {
	local OLD_TAXONOMY_FILE="${1?}"
	local OUTPUT_NEW_TAXONOMY_FILE="${2?}"
	local DIR_GTDBTK_TAX_RESULTS="$3"
	
	# FORMATO DA TAXONOMIA DO GTDB (Nao tem HEADER e 2 Colunas):
	# GCA_048462655.1 d__Archaea;p__Methanobacteriota;c__Methanobacteria;o__Methanobacteriales;f__Methanobacteriaceae;g__Methanocatella;s__Methanocatella smithii
	
	# 0. Copiar a taxonomia antiga para o novo arquivo
	cp "$OLD_TAXONOMY_FILE" "$OUTPUT_NEW_TAXONOMY_FILE" \
		|| { echo "[ERRO] Nao foi possivel copiar $OLD_TAXONOMY_FILE para $OUTPUT_NEW_TAXONOMY_FILE" >> "$LOG_FILE" ; return 1 ; }
	
	# Adicionar coluna com a origem da classificacaotaxonomica no final de cada linha
	local CLASSIFICACAO_GTDB="GTDB Release R232"
	sed -i "s/$/\t$CLASSIFICACAO_GTDB/" "$OUTPUT_NEW_TAXONOMY_FILE"
	
	# Adicionar HEADER a tabela final
	sed -i '1i Accession\tTaxonomy\tClassification_By' "$OUTPUT_NEW_TAXONOMY_FILE"
	
	# 1. Checar se o dir do gtdbtk existe
	if [ -n "$DIR_GTDBTK_TAX_RESULTS" ] && [ -d "$DIR_GTDBTK_TAX_RESULTS" ]; then
		# Se existir, concatenar as linhas da classificao
		echo "[INFO] Adicionando as classificacoes taxonomicas do GTDB-TK" >> "$LOG_FILE"
		add_gtdbtk_taxonomy_table "$OUTPUT_NEW_TAXONOMY_FILE" "$DIR_GTDBTK_TAX_RESULTS"
	else
		# Se nao existir, apenas prosseguir com a funcao
		echo "[INFO] Classificacao taxonomica completa! Nao foi necessario buscar taxonomia com GTDB-TK" >> "$LOG_FILE"
	fi


}

add_gtdbtk_taxonomy_table () {
	local OUTPUT_NEW_TAXONOMY_FILE="${1?}"
	local DIR_GTDBTK_TAX_RESULTS="${2?}"
	local GTDBTK_ARCHAEA_TAX="${DIR_GTDBTK_TAX_RESULTS}/classify/gtdbtk.ar53.summary.tsv"
	local GTDBTK_BACTERIA_TAX="${DIR_GTDBTK_TAX_RESULTS}/classify/gtdbtk.bac120.summary.tsv"
	local GTDBTK_VER="2.7.2"
	local CLASSIFICACAO_GTDBTK="GTDB-TK Version $GTDBTK_VER"

	# FORMATO DA TAXONOMIA DO GTDB-TK (Tem HEADER e mais de 2 Colunas)
	# user_genome     classification ...
	# GCA_000744755.1_ASM74475v1_genomic.fna  d__Bacteria;p__Bacillota;c__Bacilli;o__Bacillales;f__Anoxybacillaceae;g__Geobacillus;s__Geobacillus icigianus

	# 2. Verificar se pelo menos um dos arquivos de taxonomia existe
	if [[ ! -f "$GTDBTK_ARCHAEA_TAX" && ! -f "$GTDBTK_BACTERIA_TAX" ]]; then
		echo "[ERRO] Nenhum dos arquivos de taxonomia ($GTDBTK_ARCHAEA_TAX ou $GTDBTK_BACTERIA_TAX) foi encontrado." >> "$LOG_FILE"
		return 1
	fi
	
	# Incluindo classificacoes de Archaea (id + taxonomia + origem)
	if [ -f "$GTDBTK_ARCHAEA_TAX" ]; then
		awk -F'\t' -v origem="$CLASSIFICACAO_GTDBTK" '
		NR > 1 { # pula o HEADER
		
			arq_genoma = $1
			taxonomia = $2
			id_genoma = ""			
			if (match(arq_genoma, /GC[AF]_[0-9]+\.[0-9]+/)) {
				id_genoma = substr(arq_genoma, RSTART, RLENGTH)
			}
			print id_genoma "\t" taxonomia "\t" origem
			
		}' "$GTDBTK_ARCHAEA_TAX" >> "$OUTPUT_NEW_TAXONOMY_FILE" \
			|| { echo "[ERRO] Nao foi possivel adicionar taxonomia de Bacteria na funcao ${FUNCNAME[0]}" >> "$LOG_FILE" ; return 1 ; }
		echo "Taxonomia de arqueias remanescentes concatenada em $OUTPUT_NEW_TAXONOMY_FILE" >> "$LOG_FILE"
	fi

	# Incluindo classificacoes de Bacteria (id + taxonomia + origem)
	if [ -f "$GTDBTK_BACTERIA_TAX" ]; then
		awk -F'\t' -v origem="$CLASSIFICACAO_GTDBTK" '
		NR > 1 { # pula o HEADER
			
			arq_genoma = $1
			taxonomia = $2
			id_genoma = ""
			if (match(arq_genoma, /GC[AF]_[0-9]+\.[0-9]+/)) {
				id_genoma = substr(arq_genoma, RSTART, RLENGTH)
			}
			print id_genoma "\t" taxonomia "\t" origem
			
		}' "$GTDBTK_BACTERIA_TAX" >> "$OUTPUT_NEW_TAXONOMY_FILE" \
			|| { echo "[ERRO] Nao foi possivel adicionar taxonomia de Bacteria na funcao ${FUNCNAME[0]}" >> "$LOG_FILE" ; return 1 ; }
		echo "Taxonomia de bacterias remanescentes concatenada em $OUTPUT_NEW_TAXONOMY_FILE" >> "$LOG_FILE"
	fi

}