#!/usr/bin/env bash

# Escrito por Joao Pedro Castro (joao.pedro.rocha@ufv.br)
# Em 06/2026

# Versao em que foi testado (no cluster):
# GNU bash, version 4.4.20(1)-release (x86_64-redhat-linux-gnu) 

# Ideia de nome: Construcao e identificacao de genomas de procariotos extremofilos

############# LEITURA ####################

# Chamada do script: Nome-Script.sh <taxon_analisado> -flags

# Verificando argumentos do script
if [[ "$#" -eq 0 ]]; then
    echo "[ERRO] Nenhum argumento informado" >&2
    echo "[ERRO] Uso: $0 <taxon_analisado> -flags" >&2
    echo "Para mais informacoes: $0 --help"
    exit 0
fi

# Valores default dos argumentos
DATA_ATUAL="$(date +"%Y-%m-%d--%H_%M_%S")"
DEF_OUTPUT_DIR="Resultados-$DATA_ATUAL"
DEF_TAXID=""
DEF_NOME_JOB="Cluster-Execucao"
DEF_LOCAL_EXECUCAO="cluster"
DEF_MEMORIA_RAM="22" # Com 16GB - tenho erro no CheckM2 para 2500 genomas de Arqueia
DEF_NUMERO_CPU="24"
DEF_FILA_CLUSTER="roteamento"

# Lendo argumento e flags
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            cat <<EOF
CONSTRUCAO DE BANCO DE DADOS DE PROCARIOTOS
 
Pipeline para recuperacao de genomas de procariotos, identificacao de grupo de extremofilos, filtragem por qualidade e classificacao taxonomica
 
Uso: $0 <nome_taxon_analisado> -flags 
 
Flags
-o / --output_dir <string>
       nome do diretorio de output (default: ${DEF_OUTPUT_DIR%-$DATA_ATUAL}-%Y-%m-%d--%H_%M_%S)
-t / --taxid
        ID taxonomico do organismo, caso o programa nao esteja reconhecendo o nome do taxon dado
-e / --execution <cluster:pessoal> 
       local de execucao do programa (default: $DEF_LOCAL_EXECUCAO)
-j / --job_name
        Nome do job que sera submetido para o cluster, caso o local de execucao seja no cluster (default: $DEF_NOME_JOB)
-r / --ram_memory <num>
        quantidade de memoria em GB utilizada para execucao no cluster (default: ${DEF_MEMORIA_RAM}GB)
-c / --cpu <num>
        numero de cpus utilizada para execucao no cluster (default: $DEF_NUMERO_CPU)
-f / --fila_cluster <qtime:roteamento:high-mem>
        fila do cluster em que sera submetido o job (default: $DEF_FILA_CLUSTER)
EOF
            exit 0
            ;;
        -o|--output_dir)
            OUTPUT_DIR="$2"
            [ -z "$OUTPUT_DIR" ] && { echo "[ERRO]: Nenhum argumento informado para a flag --output_dir" >&2; exit 1; }
            shift 2
            ;;
        -t|--taxid)
            TAXID="$2"
            [ -z "$TAXID" ] && { echo "[ERRO]: Nenhum argumento informado para a flag --taxid" >&2; 
            exit 1; }
            [[ ! "$TAXID" =~ ^[0-9]+$ ]] && { echo "[ERRO]: Argumento para a flag --taxid deve ser numerico: '$TAXID'" >&2; exit 1; }
            shift 2
            ;;
        -e|--execution)
            LOCAL_EXECUCAO="$2"
            [ -z "$LOCAL_EXECUCAO" ] && { echo "[ERRO]: Nenhum argumento informado para a flag --execution" >&2; exit 1; }
            [[ "$LOCAL_EXECUCAO" != "cluster" && "$LOCAL_EXECUCAO" != "pessoal" ]] && { echo "[ERRO]: Argumento para a flag --execution invalido: '$LOCAL_EXECUCAO'" >&2; exit 1; } 
            shift 2
            ;;
        -j|--job_name)
            NOME_JOB="$2"
            [ -z "$NOME_JOB" ] && { echo "[ERRO]: Nenhum argumento informado para a flag --job_name" >&2; exit 1; }
            shift 2
            ;;
        -r|--ram_memory)
            MEMORIA_RAM="$2"
            [ -z "$MEMORIA_RAM" ] && { echo "[ERRO]: Nenhum argumento informado para a flag --ram_memory" >&2; exit 1; }
            [[ ! "$MEMORIA_RAM" =~ ^[0-9]+$ ]] && { echo "[ERRO]: Argumento para a flag --ram_memory deve ser numerico: '$MEMORIA_RAM'" >&2; exit 1; }
            shift 2
            ;;
        -c|--cpu)
            NUMERO_CPU="$2"
            [ -z "$NUMERO_CPU" ] && { echo "[ERRO]: Nenhum argumento informado para a flag --cpu" >&2; exit 1; }
            [[ ! "$NUMERO_CPU" =~ ^[0-9]+$ ]] && { echo "[ERRO]: Argumento para a flag --cpu deve ser numerico: '$NUMERO_CPU'" >&2; exit 1; }
            shift 2
            ;;
        -f|--fila_cluster)
            FILA_CLUSTER="$2"
            [ -z "$FILA_CLUSTER" ] && { echo "[ERRO]: Nenhum argumento informado para a flag --fila_cluster" >&2; exit 1; }
            [[ "$FILA_CLUSTER" != "qtime" && "$FILA_CLUSTER" != "roteamento" && "$FILA_CLUSTER" != "high_mem" ]] && { echo "[ERRO]: Argumento para a flag --fila_cluster invalido: '$FILA_CLUSTER'" >&2; exit 1; }
            shift 2
            ;;
        -*)
            echo "[ERRO] Flag invalida: $1" >&2
            exit 1
            ;;
        *) # Leitura do taxon informado
            if [[ -z "$TAXON" ]]; then
                TAXON="${1^^}"
            else
                TAXON+="_${1^^}"
            fi
            shift 1
            ;;
    esac
done
if [[ -z "$TAXON" ]]; then
    echo "[ERRO]: Argumento princial nao informado: Taxon" >&2
    echo "[ERRO] Uso: $0 <taxon_analisado> -flags" >&2
    exit 1
fi

############### INICIALIZACAO #########################

# Inicializando argumentos gerais (valor default se estiver vazio)
OUTPUT_DIR="${OUTPUT_DIR:-"${TAXON}-${DEF_OUTPUT_DIR}"}"
TAXID="${TAXID:-"$DEF_TAXID"}"
LOG_FILE="GENOMES-ANALYSIS.log"

# Verificando argumentos gerais
if [[ -d "$OUTPUT_DIR" ]]; then
    echo "[AVISO] Diretorio $OUTPUT_DIR ja existe"
    read -p "Continuar execucao dentro dele? [S/N]: " resposta 
    if [[ "$resposta" == "S" || "$resposta" == "s" ]]; then
        echo -e "\n\n===== REINICIANDO EXECUCAO =====\n\n" >> "${OUTPUT_DIR}/${LOG_FILE}"
    else
        echo "Fim da execucao"
        exit 0
    fi
else
    # Criando diretorio de resultados e arquivo log dentro do diretorio 
    mkdir "$OUTPUT_DIR" || { echo "[ERRO] Diretorio $OUTPUT_DIR ja existe!" >&2 ; exit 1 ; }
    > "${OUTPUT_DIR}/${LOG_FILE}" || { echo "[ERRO] Nao foi possivel criar $LOG_FILE em $OUTPUT_DIR !" >&2 ; exit 1 ; }
fi
echo "[AVISO] Resultados estao sendo salvos em $OUTPUT_DIR"
echo "[AVISO] Arquivo log com erros e informacoes da execucao disponivel em $LOG_FILE"

# Inicializando argumentos para execucao no cluster (valor default se estiver vazio)
LOCAL_EXECUCAO="${LOCAL_EXECUCAO:-"$DEF_LOCAL_EXECUCAO"}"
NOME_JOB="${NOME_JOB:-"$DEF_NOME_JOB"}"
MEMORIA_RAM="${MEMORIA_RAM:-"$DEF_MEMORIA_RAM"}"
NUMERO_CPU="${NUMERO_CPU:-"$DEF_NUMERO_CPU"}"
FILA_CLUSTER="${FILA_CLUSTER:-"$DEF_FILA_CLUSTER"}"
WALLTIME_MAX="" # definicao feita abaixo 

# Verificando argumentos para execucao no cluster
if [[ "$LOCAL_EXECUCAO" == "cluster" ]]; then
    filas=( "roteamento" "qtime" "high_mem" )
    min_cpu_por_no=( 1 1 1 )
    max_cpu_por_no=( 24 24 64 )
    min_ram_gb=( 0 0 25 )
    max_ram_gb=( 24 24 512 )
    walltime_maximo=( "2160:00:00" "72:00:00" "2160:00:00" )

    # Limites de CPU, RAM e WALLTIME para cada fila
    for ((indice=0; indice<=2; indice++)); do
        fila="${filas["$indice"]}"
        min_cpu="${min_cpu_por_no["$indice"]}"
        max_cpu="${max_cpu_por_no["$indice"]}"
        min_ram="${min_ram_gb["$indice"]}"
        max_ram="${max_ram_gb["$indice"]}"
        walltime="${walltime_maximo["$indice"]}"
        if [[ "$FILA_CLUSTER" == "$fila" ]]; then
            if [[ ! ( "$NUMERO_CPU" -ge "$min_cpu" && "$NUMERO_CPU" -le "$max_cpu" ) ]]; then
                {
                echo "[ERRO] Numero de CPU informado fora dos limites: ${NUMERO_CPU}"
                echo "[ERRO] Minimo de CPU: $min_cpu"
                echo "[ERRO] Maximo de CPU: $max_cpu"
                } >&2
                exit 1
            fi
            if [[ ! ( "$MEMORIA_RAM" -ge "$min_ram" && "$MEMORIA_RAM" -le "$max_ram" ) ]]; then
                {
                echo "[ERRO] Quantidade de memoria RAM informada fora dos limites: ${MEMORIA_RAM}"
                echo "[ERRO] Minimo de RAM: $min_ram"
                echo "[ERRO] Maximo de RAM: $max_ram"
                } >&2
                exit 1
            fi
            WALLTIME_MAX="$walltime"
            break
        fi
    done
fi

################# EXECUCAO NO COMPUTADOR PESSOAL ############################

if [[ "$LOCAL_EXECUCAO" == "pessoal" ]]; then

    # Imprimindo parametros selecionados 
    cat << EOF >> "${OUTPUT_DIR}/$LOG_FILE"
===== CONSTRUCAO DE BANCO DE DADOS DE PROCARIOTOS =====

Argumentos informados
Local da execucao: $LOCAL_EXECUCAO
Taxon analisado: $TAXON

EOF

    # Ajustando caminho de LOG_FILE
    LOG_FILE="$(realpath "${OUTPUT_DIR}/$LOG_FILE")"

    # Carregando modulos
    DIR_MODULOS="Functions_2"
    FUNCAO_PRINCIPAL="Main-Function_2.sh"
    MODULOS_EXECUCAO=( 
    "1_Download-Dehydrated-Genomes.sh"
    "2_Get-Metadata-Dehydrated-Genomes.sh"
    "3_Filter-Raw-Metadata.sh"
    "4_Categorize-Metadata-By-Group.sh"
    "5_Rehydrate-Genomes-From-Category.sh"
    "6_Filter-Genomes-By-Number-of-Gaps.sh"
    "7_Filter-Genomes-By-CheckM2.sh"
    "8_Create-Taxonomy-Classification-File.sh"
    "9_Find-Missing-Taxonomy.sh"
    "10_Create-Taxonomy-Directory-Structure.sh"
    "11_Desreplicate-Curated-Genomes.sh"
    "Funcoes_Auxiliares.sh"
    )
    
    if [[ ! -d "$DIR_MODULOS" ]]; then
        { echo "[ERRO] Diretorio $DIR_MODULOS nao foi encontrado!" >> "$LOG_FILE" ; exit 1 ; }
    fi
    for modulo in "$FUNCAO_PRINCIPAL" "${MODULOS_EXECUCAO[@]}"; do
    
        [[ -z "$modulo" ]] && continue
        caminho_modulo="${DIR_MODULOS}/${modulo}"
        if [[ -f "$caminho_modulo" ]]; then
            source "$caminho_modulo" || { echo "[ERRO] Na execucao do modulo $modulo em $DIR_MODULOS!" >> "$LOG_FILE" ; exit 1 ; }
        else
            echo "[ERRO] Modulo $caminho_modulo nao foi encontrado em $(pwd)!" >> "$LOG_FILE"
            exit 1
        fi
    done
    
    # Mudando para o diretorio de resultados
    cd "$OUTPUT_DIR" || { echo "[ERRO] Nao foi possivel mudar para dir $OUTPUT_DIR" >> "$LOG_FILE" ; exit 1 ; } 
    echo "[AVISO] Execucao do script sera feita dentro do dir $OUTPUT_DIR"
    
    # # Chamada da funcao principal
    # Uso: create_curated_database <taxon_analisado> <taxid=OPCIONAL>
    create_curated_database "$TAXON" "$TAXID" || { echo "Funcao principal falhou! Fim do programa" >> "$LOG_FILE" ; exit 1 ; }
fi

################# EXECUCAO NO CLUSTER ############################

if [[ "$LOCAL_EXECUCAO" == "cluster" ]]; then 

    NOME_PBS="job_temporario.pbs"
    
    # Lembrete - limpar modulos externos antes de executar o script (para evitar erro no carregamento)
    echo "[AVISO] Lembre-se de descarregar todos os modulos do no de login com: 'module purge'"
    echo "[AVISO] Evita erros no carregamento dos programas"

    # Imprimindo parametros selecionados 
    cat << EOF >> "${OUTPUT_DIR}/$LOG_FILE"
#### Gerador de bancos de dados de procariotos ####

Argumentos informados
Local da execucao: $LOCAL_EXECUCAO
Taxon analisado: $TAXON

Parametros para execucao no cluster
NOME_JOB: "$NOME_JOB"
FILA_CLUSTER: "$FILA_CLUSTER"
NUMERO_CPU: "$NUMERO_CPU"
MEMORIA_RAM: "$MEMORIA_RAM"

EOF

    # Criando script PBS com os parametros escolhidos ('EOF' com aspas - cria o texto literal
    cat <<'EOF' > "$NOME_PBS"
#!/usr/bin/env bash

# Mudando para o diretorio em que o PBS foi submetido (comando qsub)
cd "${PBS_O_WORKDIR}" || exit
source "/etc/profile.d/modules.sh"

# Ajustando caminho de LOG_FILE
LOG_FILE="$(realpath "${OUTPUT_DIR}/$LOG_FILE")"

# Carregar modulos externos
module load ncbi_datasets/18.26.0 taxonkit/0.20.0 checkm2/1.1.0 gtdbtk/2.7.2 skder/1.3.6 seqkit/2.12.0 \
|| { echo "Nao foi possivel carregar os modulos externos" >> "$LOG_FILE" ; exit 1 ; }

# Carregando modulos
DIR_MODULOS="Functions_2"
FUNCAO_PRINCIPAL="Main-Function_2.sh"
MODULOS_EXECUCAO=( 
"1_Download-Dehydrated-Genomes.sh"
"2_Get-Metadata-Dehydrated-Genomes.sh"
"3_Filter-Raw-Metadata.sh"
"4_Categorize-Metadata-By-Group.sh"
"5_Rehydrate-Genomes-From-Category.sh"
"6_Filter-Genomes-By-Number-of-Gaps.sh"
"7_Filter-Genomes-By-CheckM2.sh"
"8_Create-Taxonomy-Classification-File.sh"
"9_Find-Missing-Taxonomy.sh"
"10_Create-Taxonomy-Directory-Structure.sh"
"11_Desreplicate-Curated-Genomes.sh"
"Funcoes_Auxiliares.sh"
)
if [[ ! -d "$DIR_MODULOS" ]]; then
    { echo "[ERRO] Diretorio $DIR_MODULOS nao foi encontrado!" >> "$LOG_FILE" ; exit 1 ; }
fi
for modulo in "$FUNCAO_PRINCIPAL" "${MODULOS_EXECUCAO[@]}"; do
    [[ -z "$modulo" ]] && { echo "Variavel modulo esta vazia: 'modulo'" >> "$LOG_FILE" ; exit 1 ; }
    caminho_modulo="${DIR_MODULOS}/${modulo}"
    if [[ -f "$caminho_modulo" ]]; then
        source "$caminho_modulo" || { echo "[ERRO] Na execucao do modulo $modulo em $DIR_MODULOS!" >> "$LOG_FILE" ; exit 1 ; }
    else
        echo "[ERRO] Modulo $caminho_modulo nao foi encontrado em $(pwd)!" >> "$LOG_FILE"
        exit 1
    fi
done

# Mudando para o diretorio de resultados
cd "$OUTPUT_DIR" || { echo "[ERRO] Nao foi possivel mudar para dir $OUTPUT_DIR" >> "$LOG_FILE" ; exit 1 ; } 
echo "[AVISO] Execucao do script sera feita dentro de $OUTPUT_DIR" >> "$LOG_FILE" 

# Chamada da funcao principal
create_curated_database "$TAXON" "$TAXID" \
|| { echo "Funcao principal falhou! Fim do programa" >> "$LOG_FILE" ; exit 1 ; }
EOF
    # Submetendo o job com qsub (flag -V: importa todas as variaveis para o no de execucao / NAO importa funcoes nem arrays)
    echo "[AVISO] Submetendo job para fila $FILA_CLUSTER com nome $NOME_JOB"
    
    qsub \
      -N "$NOME_JOB" \
      -q "$FILA_CLUSTER" \
      -l "nodes=1:ppn=$NUMERO_CPU,mem=${MEMORIA_RAM}gb,walltime=$WALLTIME_MAX" \
      -v LOG_FILE="$LOG_FILE",OUTPUT_DIR="$OUTPUT_DIR",TAXON="$TAXON",TAXID="$TAXID",NUMERO_CPU="$NUMERO_CPU",MEMORIA_RAM="$MEMORIA_RAM",LOCAL_EXECUCAO="$LOCAL_EXECUCAO"\
      "$NOME_PBS" || { echo "Nao foi possivel submeter o job $NOME_PBS com qsub" >> "$LOG_FILE" ; exit 1 ; }

fi

