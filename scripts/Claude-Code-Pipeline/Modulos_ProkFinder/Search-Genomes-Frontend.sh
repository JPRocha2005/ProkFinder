###### MODULO DE INTERACAO COM O USUARIO - BUSCA DE GENOMAS (search_genomes) ######
#
# Front-end do comando "search_genomes": le e valida os criterios informados
# pelo usuario (via flags ou modo interativo), delega a busca propriamente
# dita para o back-end (Search-Genomes-Backend.sh) e apresenta/exporta os
# resultados.
#
# Chamada: ./Claude-Main-Hub.sh search_genomes [flags]
#          ./Claude-Main-Hub.sh search_genomes            (entra em modo interativo)
#          ./Claude-Main-Hub.sh search_genomes --help
#
# Fontes dos dados cruzados nessa busca (ver tambem Search-Genomes-Backend.sh):
# - NCBI Datasets/dataformat (metadados de assembly, amostra, qualidade)
#   https://www.ncbi.nlm.nih.gov/datasets/docs/v2/reference-docs/command-line/dataformat/
# - GTDB - Genome Taxonomy Database (taxonomia)
#   https://gtdb.ecogenomic.org/
# - BacDive - Bacterial Diversity Metadatabase (dados fenotipicos/cultivo),
#   acessado via pacote bacdive-api
#   https://github.com/JKoblitz/bacdive-api

# --- VALORES VALIDOS PARA CAMPOS CATEGORICOS ---
SG_TIPOS_GENOMA_VALIDOS=( "isolado" "mag" )
SG_NIVEIS_ASSEMBLY_VALIDOS=( "contig" "scaffold" "chromosome" "complete_genome" )
SG_OPERADORES_VALIDOS=( "<" "<=" ">" ">=" "==" "=" )


################################################################################
# AJUDA
################################################################################

mostrar_ajuda_search_genomes () {
	cat <<EOF
Uso: $0 search_genomes [flags]

Busca rapida de genomas de procariotos cruzando dados gerais (NCBI/GTDB),
ambientais, de assembly e fenotipicos/de cultivo (BacDive) - dados que os
bancos originais nao permitem cruzar diretamente entre si.

Se nenhuma flag for informada, o comando entra em MODO INTERATIVO e pergunta
os criterios um a um (deixe em branco para pular um criterio).

DADOS GERAIS
  --organismo <texto>           Nome do organismo no NCBI (match parcial)
  --taxid-ncbi <numero>          ID taxonomico do organismo no NCBI
  --taxonomia-gtdb <texto>       Taxonomia no GTDB. Aceita a taxonomia
                                  completa (d__...;p__...;...;s__...) ou
                                  apenas um dos taxons (ex: "g__Bacillus")
  --taxonomia-ncbi <texto>       Taxonomia no NCBI (nome do taxon)

DADOS AMBIENTAIS
  --pais <texto>                 Pais de origem do isolado/amostra
  --fonte-isolamento <texto>     Fonte de isolamento (ex: "soil", "hot spring")

DADOS DO ASSEMBLY
  --tipo-genoma <isolado:mag>    Genoma de isolado ou MAG
  --nivel-assembly <nivel>       ${SG_NIVEIS_ASSEMBLY_VALIDOS[*]}

DADOS FENOTIPICOS (BacDive)
  --temperatura <op><valor>      Temperatura otima de crescimento (C)
  --ph <op><valor>                pH otimo de crescimento
  --salinidade <op><valor>       Salinidade otima de crescimento (%)
                                  <op> pode ser: ${SG_OPERADORES_VALIDOS[*]}
                                  Exemplos: --temperatura ">60"
                                            --ph "<=5"
                                            --salinidade "==10"

  -h, --help                     Mostra esta ajuda

Ao final da busca, o comando mostra as 10 primeiras linhas e o total de
genomas encontrados, e pergunta se voce deseja exportar 3 tabelas separadas
(metadados, taxonomia e dados de cultivo) apenas com os genomas encontrados.
EOF
}


################################################################################
# LEITURA DOS ARGUMENTOS / MODO INTERATIVO
################################################################################

# Separa operador (<,<=,>,>=,==,=) de um valor numerico, ex: ">60" -> ">" e "60"
# Preenche as variaveis globais OPERADOR_PARSEADO e VALOR_PARSEADO
parse_operador_valor () {
	local ENTRADA="${1?}"
	local NOME_CAMPO="${2?}"

	if [[ "$ENTRADA" =~ ^(\>=|\<=|==|=|\>|\<)[[:space:]]*(-?[0-9]+([.][0-9]+)?)$ ]]; then
		OPERADOR_PARSEADO="${BASH_REMATCH[1]}"
		VALOR_PARSEADO="${BASH_REMATCH[2]}"
		return 0
	fi

	log_erro "Formato invalido para $NOME_CAMPO: '$ENTRADA' (use operador+valor, ex: '>60', '<=7.5', '==37')"
	return 1
}

ler_argumentos_search_genomes () {
	# Inicializando variaveis globais da busca (prefixo SG_ = Search Genomes)
	SG_ORGANISMO=""
	SG_TAXID_NCBI=""
	SG_TAXONOMIA_GTDB=""
	SG_TAXONOMIA_NCBI=""
	SG_PAIS=""
	SG_FONTE_ISOLAMENTO=""
	SG_TIPO_GENOMA=""
	SG_NIVEL_ASSEMBLY=""
	SG_TEMP_OPERADOR=""; SG_TEMP_VALOR=""
	SG_PH_OPERADOR=""; SG_PH_VALOR=""
	SG_SALINIDADE_OPERADOR=""; SG_SALINIDADE_VALOR=""

	# Sem nenhuma flag informada -> modo interativo
	if [[ "$#" -eq 0 ]]; then
		modo_interativo_search_genomes
		return $?
	fi

	while [[ "$#" -gt 0 ]]; do
		case "$1" in
			-h|--help)             mostrar_ajuda_search_genomes; exit 0 ;;
			--organismo)            SG_ORGANISMO="$2"; shift 2 ;;
			--taxid-ncbi)           SG_TAXID_NCBI="$2"; shift 2 ;;
			--taxonomia-gtdb)       SG_TAXONOMIA_GTDB="$2"; shift 2 ;;
			--taxonomia-ncbi)       SG_TAXONOMIA_NCBI="$2"; shift 2 ;;
			--pais)                 SG_PAIS="$2"; shift 2 ;;
			--fonte-isolamento)     SG_FONTE_ISOLAMENTO="$2"; shift 2 ;;
			--tipo-genoma)          SG_TIPO_GENOMA="$(echo "$2" | tr '[:upper:]' '[:lower:]')"; shift 2 ;;
			--nivel-assembly)       SG_NIVEL_ASSEMBLY="$(echo "$2" | tr '[:upper:]' '[:lower:]')"; shift 2 ;;
			--temperatura)
				parse_operador_valor "$2" "--temperatura" || return 1
				SG_TEMP_OPERADOR="$OPERADOR_PARSEADO"; SG_TEMP_VALOR="$VALOR_PARSEADO"
				shift 2 ;;
			--ph)
				parse_operador_valor "$2" "--ph" || return 1
				SG_PH_OPERADOR="$OPERADOR_PARSEADO"; SG_PH_VALOR="$VALOR_PARSEADO"
				shift 2 ;;
			--salinidade)
				parse_operador_valor "$2" "--salinidade" || return 1
				SG_SALINIDADE_OPERADOR="$OPERADOR_PARSEADO"; SG_SALINIDADE_VALOR="$VALOR_PARSEADO"
				shift 2 ;;
			*)
				log_erro "Flag desconhecida em search_genomes: $1"
				mostrar_ajuda_search_genomes
				return 1 ;;
		esac
	done
}

# Pergunta um valor livre (texto/numero), aceitando resposta em branco (= pular criterio)
perguntar_campo_livre () {
	local PERGUNTA="${1?}"
	local RESPOSTA
	read -r -p "$PERGUNTA" RESPOSTA
	echo "$RESPOSTA"
}

# Pergunta um campo do tipo operador+valor (temperatura/pH/salinidade), repetindo
# ate receber um formato valido ou uma resposta em branco
perguntar_campo_fenotipico () {
	local NOME_CAMPO="${1?}"
	local RESPOSTA
	while true; do
		read -r -p "$NOME_CAMPO (formato: <operador><valor>, ex: '>60'; ou ENTER para pular): " RESPOSTA
		[[ -z "$RESPOSTA" ]] && { echo ""; echo ""; return 0; }
		if parse_operador_valor "$RESPOSTA" "$NOME_CAMPO"; then
			echo "$OPERADOR_PARSEADO"
			echo "$VALOR_PARSEADO"
			return 0
		fi
		echo "Tente novamente."
	done
}

modo_interativo_search_genomes () {
	echo ""
	echo "===== BUSCA DE GENOMAS (modo interativo) ====="
	echo "Pressione ENTER para pular qualquer criterio que nao queira usar."
	echo ""

	echo "--- Dados gerais ---"
	SG_ORGANISMO="$(perguntar_campo_livre "Nome do organismo (NCBI): ")"
	SG_TAXID_NCBI="$(perguntar_campo_livre "TaxID (NCBI): ")"
	SG_TAXONOMIA_GTDB="$(perguntar_campo_livre "Taxonomia GTDB (completa ou apenas um rank, ex: g__Bacillus): ")"
	SG_TAXONOMIA_NCBI="$(perguntar_campo_livre "Taxonomia NCBI: ")"

	echo ""
	echo "--- Dados ambientais ---"
	SG_PAIS="$(perguntar_campo_livre "Pais de origem: ")"
	SG_FONTE_ISOLAMENTO="$(perguntar_campo_livre "Fonte de isolamento: ")"

	echo ""
	echo "--- Dados do assembly ---"
	SG_TIPO_GENOMA="$(perguntar_campo_livre "Tipo de genoma (isolado/mag): " | tr '[:upper:]' '[:lower:]')"
	SG_NIVEL_ASSEMBLY="$(perguntar_campo_livre "Nivel do assembly (contig/scaffold/chromosome/complete_genome): " | tr '[:upper:]' '[:lower:]')"

	echo ""
	echo "--- Dados fenotipicos (BacDive) ---"
	{ read -r SG_TEMP_OPERADOR; read -r SG_TEMP_VALOR; } < <(perguntar_campo_fenotipico "Temperatura otima de crescimento (C)")
	{ read -r SG_PH_OPERADOR; read -r SG_PH_VALOR; } < <(perguntar_campo_fenotipico "pH otimo de crescimento")
	{ read -r SG_SALINIDADE_OPERADOR; read -r SG_SALINIDADE_VALOR; } < <(perguntar_campo_fenotipico "Salinidade otima de crescimento (%)")

	echo ""
}


################################################################################
# VALIDACAO
################################################################################

validar_valor_em_lista () {
	local VALOR="$1" NOME="$2"; shift 2
	local LISTA=( "$@" ) OPCAO
	[[ -z "$VALOR" ]] && return 0
	for OPCAO in "${LISTA[@]}"; do
		[[ "$VALOR" == "$OPCAO" ]] && return 0
	done
	log_erro "Valor invalido para $NOME: '$VALOR' (opcoes: ${LISTA[*]})"
	return 1
}

validar_argumentos_search_genomes () {
	local FALHOU=0

	if [[ -n "$SG_TAXID_NCBI" && ! "$SG_TAXID_NCBI" =~ ^[0-9]+$ ]]; then
		log_erro "--taxid-ncbi deve ser numerico: '$SG_TAXID_NCBI'"
		FALHOU=1
	fi

	validar_valor_em_lista "$SG_TIPO_GENOMA" "--tipo-genoma" "${SG_TIPOS_GENOMA_VALIDOS[@]}" || FALHOU=1
	validar_valor_em_lista "$SG_NIVEL_ASSEMBLY" "--nivel-assembly" "${SG_NIVEIS_ASSEMBLY_VALIDOS[@]}" || FALHOU=1

	# Pelo menos um criterio precisa ter sido informado
	if [[ -z "$SG_ORGANISMO" && -z "$SG_TAXID_NCBI" && -z "$SG_TAXONOMIA_GTDB" && \
	      -z "$SG_TAXONOMIA_NCBI" && -z "$SG_PAIS" && -z "$SG_FONTE_ISOLAMENTO" && \
	      -z "$SG_TIPO_GENOMA" && -z "$SG_NIVEL_ASSEMBLY" && -z "$SG_TEMP_VALOR" && \
	      -z "$SG_PH_VALOR" && -z "$SG_SALINIDADE_VALOR" ]]; then
		log_erro "Nenhum criterio de busca informado"
		FALHOU=1
	fi

	[[ "$FALHOU" -eq 1 ]] && return 1
	return 0
}


################################################################################
# APRESENTACAO E EXPORTACAO DOS RESULTADOS
################################################################################

exibir_resultados_busca () {
	local ARQUIVO_RESULTADOS="${1?}"
	local TOTAL_GENOMAS

	if [[ ! -s "$ARQUIVO_RESULTADOS" ]]; then
		log_aviso "Nenhum genoma encontrado para os criterios informados"
		return 1
	fi

	TOTAL_GENOMAS="$(wc -l < "$ARQUIVO_RESULTADOS")"

	echo ""
	echo "===== RESULTADOS DA BUSCA ====="
	echo "Primeiros genomas encontrados (accession):"
	head -n 10 "$ARQUIVO_RESULTADOS"
	[[ "$TOTAL_GENOMAS" -gt 10 ]] && echo "..."
	echo ""
	echo "Total de genomas encontrados: $TOTAL_GENOMAS"
	echo "================================"
	echo ""
}

perguntar_download_resultados () {
	local ARQUIVO_RESULTADOS="${1?}"
	local RESPOSTA DIR_SAIDA_BUSCA

	read -r -p "Deseja exportar as tabelas (metadados, taxonomia e dados de cultivo) desses genomas? [S/N]: " RESPOSTA
	if [[ "$RESPOSTA" != "S" && "$RESPOSTA" != "s" ]]; then
		log_info "Exportacao das tabelas de resultados ignorada pelo usuario"
		return 0
	fi

	read -r -p "Diretorio de saida para as tabelas [default: ./search_genomes-resultados]: " DIR_SAIDA_BUSCA
	DIR_SAIDA_BUSCA="${DIR_SAIDA_BUSCA:-./search_genomes-resultados}"
	mkdir -p "$DIR_SAIDA_BUSCA" || { log_erro "Nao foi possivel criar diretorio $DIR_SAIDA_BUSCA"; return 1; }

	exportar_metadados_hits     "$ARQUIVO_RESULTADOS" "${DIR_SAIDA_BUSCA}/metadados-genomas.tsv"
	exportar_taxonomia_hits     "$ARQUIVO_RESULTADOS" "${DIR_SAIDA_BUSCA}/taxonomia-genomas.tsv"
	exportar_dados_cultivo_hits "$ARQUIVO_RESULTADOS" "${DIR_SAIDA_BUSCA}/dados-cultivo-genomas.tsv"

	log_sucesso "Tabelas exportadas em $DIR_SAIDA_BUSCA"
}


################################################################################
# ORQUESTRACAO DO COMANDO
################################################################################

verificar_bancos_referencia_disponiveis () {
	if [[ ! -f "${DIR_REFERENCIA}/COMPLETED.txt" ]]; then
		log_aviso "Bancos de dados de referencia nao encontrados/completos em $DIR_REFERENCIA"
		log_aviso "Rode o pipeline principal ao menos uma vez (ele baixa NCBI/GTDB/BacDive) antes de usar search_genomes"
	fi
}

# Uso: comando_search_genomes <flags...>
comando_search_genomes () {
	verificar_bancos_referencia_disponiveis

	ler_argumentos_search_genomes "$@" || { mostrar_ajuda_search_genomes; return 1; }
	validar_argumentos_search_genomes || { mostrar_ajuda_search_genomes; return 1; }

	log_info "Iniciando busca de genomas com os criterios informados..."

	local ARQUIVO_RESULTADOS
	ARQUIVO_RESULTADOS="$(mktemp)"

	executar_busca_genomas "$ARQUIVO_RESULTADOS" \
		|| { log_erro "Falha na execucao da busca de genomas"; rm -f "$ARQUIVO_RESULTADOS"; return 1; }

	exibir_resultados_busca "$ARQUIVO_RESULTADOS" || { rm -f "$ARQUIVO_RESULTADOS"; return 1; }

	perguntar_download_resultados "$ARQUIVO_RESULTADOS"

	rm -f "$ARQUIVO_RESULTADOS"
	return 0
}
