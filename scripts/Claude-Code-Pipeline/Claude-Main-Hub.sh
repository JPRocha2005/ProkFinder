#!/usr/bin/env bash

# PROKFINDER - Uma pipeline para busca, recuperação e curagem de genomas de 
# procariotos baseado em dados fenotípicos e metabólicos

################################################################################
# LOG
################################################################################

COR_RESET='\033[0m'
COR_VERMELHO='\033[0;31m'
COR_VERDE='\033[0;32m'
COR_AMARELO='\033[0;33m'
COR_AZUL='\033[0;34m'

log_msg () {
	local NIVEL="${1?}"; shift
	local MENSAGEM="${*?}"
	local COR TAG

	case "$NIVEL" in
		INFO)    COR="$COR_AZUL"    ; TAG="INFO"    ;;
		SUCESSO) COR="$COR_VERDE"   ; TAG="SUCESSO" ;;
		AVISO)   COR="$COR_AMARELO" ; TAG="AVISO"   ;;
		ERRO)    COR="$COR_VERMELHO"; TAG="ERRO"    ;;
		*)       COR="$COR_RESET"   ; TAG="$NIVEL"  ;;
	esac

	local CARIMBO_TEMPO
	CARIMBO_TEMPO="$(date +"%Y-%m-%d %H:%M:%S")"

	echo -e "${COR}[${CARIMBO_TEMPO}] [${TAG}]${COR_RESET} ${MENSAGEM}" >&2
	if [[ -n "${LOG_FILE:-}" ]]; then
		echo "[${CARIMBO_TEMPO}] [${TAG}] ${MENSAGEM}" >> "$LOG_FILE"
	fi
	return 0
}

log_info ()    { log_msg "INFO"    "$@" ; }
log_sucesso () { log_msg "SUCESSO" "$@" ; }
log_aviso ()   { log_msg "AVISO"   "$@" ; }
log_erro ()    { log_msg "ERRO"    "$@" ; }


################################################################################
# DEPENDENCIAS
################################################################################

verificar_dependencias () {
	local PROGRAMAS=( datasets dataformat wget unzip seqkit checkm2 taxonkit gtdbtk skder awk sort split curl jq )
	local FALTANDO=()
	local PROGRAMA

	for PROGRAMA in "${PROGRAMAS[@]}"; do
		command -v "$PROGRAMA" &> /dev/null || FALTANDO+=("$PROGRAMA")
	done

	if [[ "${#FALTANDO[@]}" -gt 0 ]]; then
		log_erro "Programas nao encontrados no PATH: ${FALTANDO[*]}"
		return 1
	fi

	local VARIAVEIS=( CHECKM2DB TAXONKIT_DATA_DIR GTDBTK_DATA_PATH NCBI_API_KEY ) ## Estranho - checar se sao esses nomes mesmo que devem ser utilizados. Acho q seria interessante ter uma instalacao das dependencias (alem da verificacao), considerando a execucao no computador pessoal e nao no cluster
	local VARS_FALTANDO=()
	local VAR

	for VAR in "${VARIAVEIS[@]}"; do
		[[ -z "${!VAR:-}" ]] && VARS_FALTANDO+=("$VAR")
	done
	[[ "${#VARS_FALTANDO[@]}" -gt 0 ]] && log_aviso "Variaveis de ambiente nao definidas: ${VARS_FALTANDO[*]}"

	log_sucesso "Dependencias verificadas"
	return 0
}


################################################################################
# DIRETORIOS
################################################################################

# Uso: criar_estrutura_diretorios <output_dir>
criar_estrutura_diretorios () {
	OUTPUT_DIR="${1?}"

	DIR_GENOMAS="${OUTPUT_DIR}/01_GENOMES"
	DIR_METADADOS="${OUTPUT_DIR}/02_METADATA"
	DIR_TAXONOMIA="${OUTPUT_DIR}/03_TAXONOMY"
	DIR_QUALIDADE="${OUTPUT_DIR}/04_QUALITY"
	DIR_RESULTADOS="${OUTPUT_DIR}/05_RESULTS"

	local DIR
	for DIR in "$OUTPUT_DIR" "$DIR_GENOMAS" "$DIR_METADADOS" "$DIR_TAXONOMIA" "$DIR_QUALIDADE" "$DIR_RESULTADOS"; do
		mkdir -p "$DIR" || { log_erro "Nao foi possivel criar o diretorio $DIR" ; return 1 ; }
	done

	log_sucesso "Estrutura de diretorios criada em $OUTPUT_DIR"
}


################################################################################
# BANCOS DE DADOS DE REFERENCIA (NCBI / GTDB / BacDive)
################################################################################
# Diretorio "global", fora do OUTPUT_DIR de cada execucao - os dados de
# referencia sao independente do taxon/categoria analisados, entao
# nao faz sentido baixa-los de novo a cada execucao da pipeline.

DIR_MODULOS="${DIR_MODULOS:-Modulos_ProkFinder}"
DIR_REFERENCIA="${DIR_REFERENCIA:-$HOME/ProkFinder/db}"
GTDB_DATABASE_LINK="https://data.gtdb.aau.ecogenomic.org/releases/latest"

# Uso: carregar_modulo_referencia
carregar_modulo_referencia () {
	local MODULO_0="${DIR_MODULOS}/0_Download-Databases-Referencia.sh"

	if [[ ! -f "$MODULO_0" ]]; then
		log_erro "Modulo nao encontrado: $MODULO_0"
		return 1
	fi

	source "$MODULO_0" || { log_erro "Falha ao carregar o modulo $MODULO_0"; return 1; }
}


################################################################################
# BUSCA DE GENOMAS (search_genomes)
################################################################################
# Modulos separados em front-end (interacao com o usuario) e back-end
# (motor de busca propriamente dito), permitindo evoluir a logica de busca
# sem mexer na interacao com o usuario e vice-versa.

# Uso: carregar_modulos_busca
carregar_modulos_busca () {
	local MODULO_BACKEND="${DIR_MODULOS}/Search-Genomes-Backend.sh"
	local MODULO_FRONTEND="${DIR_MODULOS}/Search-Genomes-Frontend.sh"
	local MODULO

	# Backend primeiro: frontend chama funcoes definidas nele
	for MODULO in "$MODULO_BACKEND" "$MODULO_FRONTEND"; do
		if [[ ! -f "$MODULO" ]]; then
			log_erro "Modulo nao encontrado: $MODULO"
			return 1
		fi
		source "$MODULO" || { log_erro "Falha ao carregar o modulo $MODULO"; return 1; }
	done
}


################################################################################
# AJUDA
################################################################################

METABOLISMOS_VALIDOS=( aerobico anaerobico anaerobico_facultativo autotrofico heterotrofico fotossintetico quimiolitotrofico quimiorganotrofico mixotrofico )
FILAS_CLUSTER_VALIDAS=( qtime roteamento high_mem )

mostrar_ajuda () {
	local TIPO_AJUDA="${1?}" # geral ou <comando>
	local LISTA_METABOLISMOS
	LISTA_METABOLISMOS="$(printf '                                  - %s\n' "${METABOLISMOS_VALIDOS[@]}")"

case "$TIPO_AJUDA" in
	geral)
cat <<EOF
Uso: prokfinder <comando> [flags]

===================== ProkFinder =====================
Recuperador de genomas curados de procariotos por 
caracteristicas fisiologicas, metabolicas e ambientais

Desenvolvido por: João Pedro Castro da Rocha
Email: joao.pedro.rocha@ufv.br

O ProkFinder é uma pipeline que integra informações de
três bancos de dados (NCBI, GTDB e BacDive), permitindo
recuperar genomas de procariotos de acordo com metadados
do genoma, dados taxônomicos e dados de cultivo do organismo,
como temperatura de crescimento, pH e salinidade.

Além disso, a pipeline posssui opcoes para fazer a curagem
dos genomas de interesse gerando um banco já curado:
- Parametros de qualidade da montagem
- Classificação taxônomica padronizada com GTDB e GTDB-TK
- Desreplicacao dos genomas redundantes com skDER
- Anotação padronizada dos genomas com Prokka

Cada modulo é independente, mas podem ser executados em conjunto
utilizando o comando download_wf ("downlad workflow").

COMANDOS
	search_genomes					-> Busca rapida pelos genomas de interesse
	download_wf						-> Workflow para download e curagem dos genomas de interesse
	filter_genomes_by_quality		-> Filtrar lista de genomas por qualidade
	classify_genomes_gtdbtk			-> Classificar taxonicamente com GTDB-TK 
	depreplicate_with_skder			-> Desreplicar genomas redundantes com skder
	annotate_genomes				-> Anotar genomas com Prokka
	
DEPENDENCIAS (informed version or higher)
	-taxonkit v.0.20.0
	-datasets v.18.26.0
	-seqkit v.2.12.0
	-checkm2 v.1.1.0
	-gtdbtk v.2.7.2
	-skder v.1.3.6
	-prokka v.1.15.6
	
Uso: prokfinder <comandos> --help para mais informacoes
EOF
;;
	search_genomes)
cat << EOF
.: search_genomes :.
Uso: prokfinder search_genomes [flags]

Busca rapida de genomas utilizando dados do assembly, amostra ou fenotipicos

[WARNING] ##Comment: here i have some options:
# 1) To make the search of genomes real fast i do a pre-calcutation of the parameters,
# like taxonomy (GTDB-TK) and quality parameters (CheckM2 completeness and contamination)
# 2) Or i dont do this, and inform the userm which searchs are fast and which arent
# 3) Exclude from the fast search tool, some paramets like:
# - Quality parameters (n° of contigs, n50, l50): use the ones informed in the assembly
# - Completeness and Contamination (or use the CheckM values that are informed in the assembly metadata)
# - Taxonomy from GTDB-TK (use only the genomes that are already classified by GTDB table)

GENERAL SEARCH FLAGS
	--organism-name <name>			Organism name (use quotes for 2 or more words). 
									Ex: --organism-name "Bacillus subtilus"
	--taxonomy <tax>				Single taxon or more separated by semicolon using rank prefix. 
									Ex: --taxonomy d__Archaea;p__Crenarchaeota
	--ncbi-taxid <id>				Taxonomy ID from NCBI that identify the species or other taxon (domain, phylum, class, ...)
									Ex: --ncbi-taxid 28889 (TaxID for Thermoproteota phylum)
	--genome-accession <id>			Accession number of genomes in GenBank (prefix 'GCA_') or ReqSeq (prefix 'GCF_'). 
									Ex: --genome-accession GCA_000195955.2
	
ASSEMBLY SEARCH FLAGS
	--assembly-level <option>		Level of concatenation of the reads from the genome: 
									contig, scaffold, chromossome, complete, all. 
									Default: all
	--assembly-origin <option>		Origin of the assembly: 
									isolate_genome, metagenome, all.
									Default: all
	--assembly-release-date <date>	Release date of assembly. Format: YEAR-MONTH-DAY. Ex: 2026-08-08
									Default: none (all dates)
	
ASSEMBLY QUALITY SEARCH FLAGS
	--max-contigs <num>          	Maximum number of contigs inside the assembly
									Default: 1000
	--min-cobertura <num>        	Mean depth of coverage (in folds)
									Default: 50
	--min-n50 <num>              	Mininum N50 length (in bp)
									Default: 5000
	--max-l50 <num>              	Minimum number of contigs for L50
									Default: 500
	--min-completeness <num>		
									Mininum completeness (in percentage)
									Default: 75
	--max-contamination <num>		
									Minimum contamination (in percentage)
									Default: 5

SAMPLE SEARCH FLAGS
	--isolation-source <local>		Place where sample of the organism was colected
									(use quotes for 2 or more words)
									Ex: "hot spring"
	--biosample-id <id>				ID of the sample in BioSample database
									Ex: "SAMEA122457804"
	
ORGANISM TRAITS SEARCH FLAGS
	--min-temp <num>             	Minumum temperature of optimum growth (in °C)
	--max-temp <num>             	Maximum temperature of optimum growth (in °C)
	--min-ph <num>               	Mininum pH of optimum growth (0-14)
	--max-ph <num>               	Maximum pH of optimum growth (0-14)
	--min-salinity <num>       		Mininum salinity of optimum growth (%)
	--max-salinity <num>       		Maximum salinity of optimum growth (%)
EOF
	download_wf)
cat << EOF
.: download_wf :.

Pipeline para selecao e curagem dos genomas
Uso: prokfinder download_wf [flags]

The pipeline works in 6 steps:
1) Choose the criteria for selecting genomes
2) Filtering the genome by quality parameters
3) Adding taxonomy classification using GTDB and GTDB-TK
4) Dereplicating genomes with skDER
5) Functional annotation with prokka
6) Generation of results in tables and graphs

For each step you can modify parameters optionally, except for the 
first step of choosing a criteria, which is necessary for you to 
pick at least one criteria for selecting the genomes:

CRITERIAS FOR SELECTING GENOMES (provide at least one):
	--accession <file>				File containing a list of genome accession number
									from GenBank (prefix GCA) or RefSeq (prefix GCF)
									Ex: accession_list.txt
										>GCA_1234578.1
										>GCA_1234579.1

	--isolation_source <file>								
									File containing one or more keyword for the isolation
									source in each line. Also accepts keywords in REGEX 
									format.
									Ex: isolation_source_list.txt
										>hot spring
										>[4-9][0-9]( deg|c)
	--taxid <file>
									TSV table containing the NCBI taxonomy ID of the species
									of other taxons in the 1° column. Optionally, the source
									from this taxid can be include in the 2° column and will
									be used in the output to track provenance.
									Ex: taxonomy_id.tsv
										>9892	doi:10.1000/xyz123
										>12021	doi:01.0110/xyz123
	--taxon <file>					
									TSV table containing the taxon name of the species (or other
									rank) in the 1° column. Optionally, the source can be include
									in the 2° column and will be used in the output to track provenance.
									[WARNING] The taxon is converted in taxid inside the system,
									be careful with misspellings. 
									Ex: taxonmy_name.tsv
										>Bacillus subtillus
										>Thermoproteota
										
	--other_traits <file>        
									List of traits to filter the genome, based on assembly 
									attributes, sample info, cultivation data and other (see 
									options below). Each trait should be separed in a new line.
									Ex: traits_list.txt
										>temp-min 45
										>assembly-level complete-genome
	
	TRAITS OPTIONS
		--temp-min <num>             Temperatura minima de crescimento (C)
		--temp-max <num>             Temperatura maxima de crescimento (C)
		--ph-min <num>                pH minimo de crescimento
		--ph-max <num>                pH maximo de crescimento
		--salinidade-min <num>       Salinidade minima de crescimento (%)
		--salinidade-max <num>       Salinidade maxima de crescimento (%)
							(min e max de cada faixa sao independentes,
							nao e necessario informar os dois)
								
PERSONALIZED NAME FOR CATEGORY (OPTIONAL)
	--category <name>			A generic name for labelling the genomes you will
								received. Ex: THERMOPHILIC, SOIL-MICROBES								
									
FILTERING GENOMES (by assembly quality):

	[INFO] The assembly quality parameters (n° of contigs, n50, l50) is calculated
	with SeqKit v.2.12.0; the mean depth of coverage is retrieved from assembly metadata
	from GenBank; the completeness and contamination are calculated using CheckM2 
	v.1.1.0.
	
	[WARNING] Since the depth of coverage is calculated as the mean, is not guarentee that
	will represent the real depth of coverage of the genomes, especially for MAGs. So, to
	avoid losing genomes from less representative/rare communities, is recommended to lower
	the mean depth of covergare value and allow a more loose filtering.
	
	--max-contigs <num>          	
									Maximum number of contigs inside the assembly
									Default: 1000
	--min-coverage <num>       		
									Mean depth of coverage (in folds)
									Default: 50
	--min-n50 <num>              	
									Mininum N50 length (in bp)
									Default: 5000
	--max-l50 <num>              	
									Minimum number of contigs for L50
									Default: 500
	--min-completeness <num>		
									CheckM2 mininum completeness (in percentage)
									Default: 75
	--max-contamination <num>		
									CheckM2 maximum contamination (in percentage)
									Default: 5

CLASSIFYING GENOMES (using GTDB and GTDB Toolkit)

	[INFO] The classication for the genomes is provided by a taxonomy table from GTDB
	initially, however since the genomes are download from GenBank and are constatly 
	being update, some of then don't the taxonomy is this table. For this cases, the 
	GTDB Toolkit (GTDB-TK) can be used to assign the taxonomy for the genomes
	
	[WARNING] GTDB-TK used a entire phyligenomic tree for taxonomy classification, as
	results it requires a lot of RAM Memory (minimum of XXX GB). Hence we offer the
	option to use NCBI taxonomy for all genomes or for only the remaning ones that were
	not classified by GTDB table
	
	--ncbi-taxonomy	<option>	Use of NCBI taxonomy for classification.
								Options: skip, only-remaining, all
								Default: skip
								
	GTDB-TK parameters
		Use: --gtdbtk help for more information
		
DEREPLICATION (using skDER)

	[INFO] skDER provide an option ot filter mobile genetic elements temporally to
	guarentee a more fair comparison between genomes of same taxonomic level (e.g. 
	species, strain). For this task, there 2 options:
	- PhiSpy (faster / filter only prophages)
	- geNomad (slower / more comprenhisive, filter prophages and plasmids)
	
	--filter-mge <option>		Program used for filtering the mobile elements (MGE)
								Options: phispy, genomad, none 
								Default: none (no mge filtering)
								
	skDER parameters
		Use: --skder help for more information
		
		
RESULTS ANALYSIS
	### COMPLETE...

GENERAL FLAGS
	-o, --output-dir <dir>       
								Diretorio de saida (default: Prokfinder-Results-<date>)
	-u, --update-reference-databases
								Forca o novo download dos bancos de dados de
								referencia (NCBI, GTDB, BacDive), mesmo que ja
								tenham sido instalados anteriormente.
								Por padrao, o download so ocorre se o arquivo
								COMPLETED.txt nao existir no diretorio de
								referencia (${DIR_REFERENCIA})
	-R, --move-reference-database
								#### MAYBE??
	-e, --execution <local|cluster>
								The pipeline can be executed locally or in a high perfomance
								cluster using the PBS. 
								Default: local
								
	CLUSTER-SPECIFIC FLAGS
		-j, --job-name <nome>        Nome do job no cluster (default: Prokfinder-Execution)
		-c, --cpu <num>               Numero de CPUs (default: 24)
		-r, --ram <num>               Memoria RAM em GB (default: 22)
		-f, --fila-cluster <fila>    Fila do PBS: ${FILAS_CLUSTER_VALIDAS[*]} (default: roteamento)
		
		[WARNING] This parameters and the internal script for cluster execution were made 
		specific to be executed in the cluster from the Federal University of Vicosa, Brasil, 
		this is not guarentee to work on any cluster using the PBS configuration.
		
	-h, --help					See this help
EOF
;;

filter_genomes_by_quality)
cat << EOF
	.: filter_genomes_by_quality :.
EOF
;;

classify_genomes_gtdbtk)
cat << EOF
	.: classify_genomes_gtdbtk :.
EOF
;;

depreplicate_with_skder)
cat << EOF
	.: depreplicate_with_skder :.
EOF
;;

annotate_genomes)
cat << EOF
	.: annotate_genomes :.
EOF
;;

esac


}


################################################################################
# LEITURA DOS ARGUMENTOS
################################################################################

ler_argumentos () {
	TAXON=""
	TAXID=""
	CATEGORIA=""
	ARQUIVO_AMBIENTES=""
	ARQUIVO_BANCOS_TAXID=""
	METABOLISMO=""
	TEMP_MIN=""; TEMP_MAX=""
	PH_MIN=""; PH_MAX=""
	SALINIDADE_MIN=""; SALINIDADE_MAX=""

	MAX_CONTIGS=1000
	MIN_COBERTURA=50
	MIN_N50=5000
	MAX_L50=500

	OUTPUT_DIR=""
	LOCAL_EXECUCAO="cluster"
	NOME_JOB="Cluster-Execucao"
	NUMERO_CPU=24
	MEMORIA_RAM=22
	FILA_CLUSTER="roteamento"
	ATUALIZAR_BANCOS_REFERENCIA="false"

	while [[ "$#" -gt 0 ]]; do
		case "$1" in
			-h|--help)               mostrar_ajuda; exit 0 ;;
			# Leitura dos comandos
			search_genomes)
			download_wf)
			filter_genomes_by_quality)
			classify_genomes_gtdbtk)
			depreplicate_with_skder)
			annotate_genomes)
			--taxon)                  TAXON="${2^^}"; shift 2 ;;
			--taxid)                  TAXID="$2"; shift 2 ;;
			--categoria)              CATEGORIA="${2^^}"; shift 2 ;;
			--arquivo-ambientes)      ARQUIVO_AMBIENTES="$2"; shift 2 ;;
			--arquivo-bancos-taxid)   ARQUIVO_BANCOS_TAXID="$2"; shift 2 ;;
			--metabolismo)            METABOLISMO="$2"; shift 2 ;;
			--temp-min)               TEMP_MIN="$2"; shift 2 ;;
			--temp-max)               TEMP_MAX="$2"; shift 2 ;;
			--ph-min)                 PH_MIN="$2"; shift 2 ;;
			--ph-max)                 PH_MAX="$2"; shift 2 ;;
			--salinidade-min)         SALINIDADE_MIN="$2"; shift 2 ;;
			--salinidade-max)         SALINIDADE_MAX="$2"; shift 2 ;;
			--max-contigs)            MAX_CONTIGS="$2"; shift 2 ;;
			--min-cobertura)          MIN_COBERTURA="$2"; shift 2 ;;
			--min-n50)                MIN_N50="$2"; shift 2 ;;
			--max-l50)                MAX_L50="$2"; shift 2 ;;
			-o|--output-dir)          OUTPUT_DIR="$2"; shift 2 ;;
			-e|--execucao)            LOCAL_EXECUCAO="$2"; shift 2 ;;
			-j|--job-name)            NOME_JOB="$2"; shift 2 ;;
			-c|--cpu)                 NUMERO_CPU="$2"; shift 2 ;;
			-r|--ram)                 MEMORIA_RAM="$2"; shift 2 ;;
			-f|--fila-cluster)        FILA_CLUSTER="$2"; shift 2 ;;
			-u|--update-reference-databases)
			                          ATUALIZAR_BANCOS_REFERENCIA="true"; shift 1 ;;
			*) log_erro "Flag desconhecida: $1" ; exit 1 ;;
		esac
	done

	OUTPUT_DIR="${OUTPUT_DIR:-"${TAXON}-${CATEGORIA}-Resultados-$(date +"%Y-%m-%d--%H_%M_%S")"}"
}


################################################################################
# VALIDACAO DOS ARGUMENTOS
################################################################################

validar_numerico () {
	local VALOR="$1" NOME="$2"
	[[ -z "$VALOR" ]] && return 0
	[[ "$VALOR" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { log_erro "Valor invalido para $NOME: '$VALOR' (deve ser numerico)"; return 1; }
}

validar_inteiro () {
	local VALOR="$1" NOME="$2"
	[[ -z "$VALOR" ]] && return 0
	[[ "$VALOR" =~ ^[0-9]+$ ]] || { log_erro "Valor invalido para $NOME: '$VALOR' (deve ser um inteiro)"; return 1; }
}

validar_faixa () {
	local NOME="$1" MIN="$2" MAX="$3"
	[[ -z "$MIN" || -z "$MAX" ]] && return 0
	awk -v a="$MIN" -v b="$MAX" 'BEGIN{exit !(a<=b)}' \
		|| { log_erro "Faixa invalida de $NOME: minimo ($MIN) maior que maximo ($MAX)"; return 1; }
}

validar_metabolismo () {
	local LISTA="$1"
	[[ -z "$LISTA" ]] && return 0

	local ITENS_BRUTOS ITEM ITEM_LIMPO OPCAO VALIDO
	IFS=',' read -ra ITENS_BRUTOS <<< "$LISTA"

	METABOLISMO_ARRAY=()
	for ITEM in "${ITENS_BRUTOS[@]}"; do
		ITEM_LIMPO="$(echo "$ITEM" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
		VALIDO=0
		for OPCAO in "${METABOLISMOS_VALIDOS[@]}"; do
			[[ "$ITEM_LIMPO" == "$OPCAO" ]] && { VALIDO=1; break; }
		done
		[[ "$VALIDO" -eq 0 ]] && { log_erro "Metabolismo invalido: '$ITEM_LIMPO'. Opcoes validas: ${METABOLISMOS_VALIDOS[*]}"; return 1; }
		METABOLISMO_ARRAY+=("$ITEM_LIMPO")
	done
}

validar_arquivo_opcional () {
	local CAMINHO="$1" NOME="$2"
	[[ -z "$CAMINHO" ]] && return 0
	[[ -f "$CAMINHO" && -s "$CAMINHO" ]] || { log_erro "$NOME nao encontrado ou vazio: $CAMINHO"; return 1; }
}

validar_pelo_menos_um_criterio () {
	[[ -n "$ARQUIVO_BANCOS_TAXID" || -n "$ARQUIVO_AMBIENTES" || -n "$METABOLISMO" \
		|| -n "$TEMP_MIN" || -n "$TEMP_MAX" || -n "$PH_MIN" || -n "$PH_MAX" \
		|| -n "$SALINIDADE_MIN" || -n "$SALINIDADE_MAX" ]] && return 0
	log_erro "Nenhum criterio para identificacao da categoria: $CATEGORIA informado (banco de taxid, ambiente, fisiologico ou metabolico)"
	return 1
}

validar_argumentos () {
	local FALHOU=0

	[[ -z "$TAXON" ]]     && { log_erro "Flag obrigatoria ausente: --taxon"; FALHOU=1; }
	[[ -z "$TAXID" ]]     && { log_erro "Flag obrigatoria ausente: --taxid"; FALHOU=1; }
	[[ -z "$CATEGORIA" ]] && { log_erro "Flag obrigatoria ausente: --categoria"; FALHOU=1; }
	validar_inteiro "$TAXID" "--taxid" || FALHOU=1

	validar_numerico "$TEMP_MIN" "--temp-min" || FALHOU=1
	validar_numerico "$TEMP_MAX" "--temp-max" || FALHOU=1
	validar_faixa "temperatura" "$TEMP_MIN" "$TEMP_MAX" || FALHOU=1

	validar_numerico "$PH_MIN" "--ph-min" || FALHOU=1
	validar_numerico "$PH_MAX" "--ph-max" || FALHOU=1
	validar_faixa "pH" "$PH_MIN" "$PH_MAX" || FALHOU=1

	validar_numerico "$SALINIDADE_MIN" "--salinidade-min" || FALHOU=1
	validar_numerico "$SALINIDADE_MAX" "--salinidade-max" || FALHOU=1
	validar_faixa "salinidade" "$SALINIDADE_MIN" "$SALINIDADE_MAX" || FALHOU=1

	validar_metabolismo "$METABOLISMO" || FALHOU=1

	validar_arquivo_opcional "$ARQUIVO_AMBIENTES" "--arquivo-ambientes" || FALHOU=1
	validar_arquivo_opcional "$ARQUIVO_BANCOS_TAXID" "--arquivo-bancos-taxid" || FALHOU=1

	validar_inteiro "$MAX_CONTIGS" "--max-contigs" || FALHOU=1
	validar_inteiro "$MIN_COBERTURA" "--min-cobertura" || FALHOU=1
	validar_inteiro "$MIN_N50" "--min-n50" || FALHOU=1
	validar_inteiro "$MAX_L50" "--max-l50" || FALHOU=1

	[[ "$LOCAL_EXECUCAO" != "cluster" && "$LOCAL_EXECUCAO" != "pessoal" ]] \
		&& { log_erro "--execucao invalido: '$LOCAL_EXECUCAO' (use cluster ou pessoal)"; FALHOU=1; }

	validar_inteiro "$NUMERO_CPU" "--cpu" || FALHOU=1
	validar_inteiro "$MEMORIA_RAM" "--ram" || FALHOU=1

	if [[ "$LOCAL_EXECUCAO" == "cluster" ]]; then
		local FILA_OK=0 OPCAO
		for OPCAO in "${FILAS_CLUSTER_VALIDAS[@]}"; do
			[[ "$FILA_CLUSTER" == "$OPCAO" ]] && { FILA_OK=1; break; }
		done
		[[ "$FILA_OK" -eq 0 ]] && { log_erro "--fila-cluster invalida: '$FILA_CLUSTER' (use ${FILAS_CLUSTER_VALIDAS[*]})"; FALHOU=1; }
	fi

	validar_pelo_menos_um_criterio || FALHOU=1

	[[ "$FALHOU" -eq 1 ]] && return 1
	log_sucesso "Argumentos validados"
	return 0
}


################################################################################
# MAIN
################################################################################

main () {
	# --- Subcomando search_genomes: nao roda o pipeline de curadoria,
	# apenas busca genomas ja presentes nos bancos de referencia baixados ---
	if [[ "${1:-}" == "search_genomes" ]]; then
		shift
		carregar_modulos_busca || exit 1
		comando_search_genomes "$@"
		exit $?
	fi

	ler_argumentos "$@"
	validar_argumentos || exit 1
	verificar_dependencias || exit 1
	criar_estrutura_diretorios "$OUTPUT_DIR" || exit 1

	LOG_FILE="${OUTPUT_DIR}/GENOMES-ANALYSIS.log"
	> "$LOG_FILE" || { log_erro "Nao foi possivel criar o arquivo de log em $LOG_FILE"; exit 1; }

	log_sucesso "Leitura de parametros e criacao de diretorios concluidas"
	log_info "Taxon: $TAXON | TaxID: $TAXID | Categoria: $CATEGORIA"
	log_info "Diretorio de saida: $OUTPUT_DIR"

	# --- Download dos bancos de dados de referencia (NCBI, GTDB, BacDive) ---
	# So baixa de fato se COMPLETED.txt nao existir em DIR_REFERENCIA, a menos
	# que --update-reference-databases (-u) tenha sido informada
	carregar_modulo_referencia || exit 1

	baixar_bancos_referencia "$DIR_REFERENCIA" "$GTDB_DATABASE_LINK" "$ATUALIZAR_BANCOS_REFERENCIA" \
		|| { log_erro "Falha no download dos bancos de dados de referencia"; exit 1; }
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi