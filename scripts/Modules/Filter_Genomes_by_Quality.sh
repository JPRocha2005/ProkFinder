#!/usr/bin/env bash

# Modulo para fazer a filtragem dos genomam:
# 1 - ordenando os contigs em ordem decrescente, removendo contigs menor que 1000 pares de bases e renomeando ("Contig_1", ex.)
# 2 - removendo genomas (ja com contigs filtrados) com N50 baixo ou muitos contigs 
# 3 - removendo genomas (ja filtrado pelo N50 e n° contigs) com completude e contaminacao do checkm2 ruim

set -u
# set -e (errexit): para a execucao caso algum comando retorne status de saida != 0
# set -u (unset): para a execucao caso tente-se usar uma variavel nao declarada
# set -o pipefail : para a execucao caso qualquer comando dentro de uma pipe retorne status de saida != 0

filtrar_genomas_qualidade() {
    local PASTA_GENOMAS="${1?}"
    local LOG="filtering_contigs.log"
    local TABELA_NUMERO_CONTIGS="numero_contigs_antes_e_depois.tsv"
    > "$LOG"
    echo -e "Contigs-antes-filtragem\tContigs-depois-filtragem" > "$TABELA_NUMERO_CONTIGS"
    
    # Valida se o arquivo de lista foi informado e se existe
    if [ ! -d "$PASTA_GENOMAS" ]; then
        log_error "Diretorio nao encontrado $PASTA_GENOMAS."
        return 1
    fi

    # Diretório de saída para os novos arquivos filtrados e ordenados
    local DIR_SAIDA="GENOMES_WITHOUT_SMALL_CONTIGS"
    criar_dir "$DIR_SAIDA"
    
    # Obtendo vetor com todos os caminhos dos genomas na pasta (encontrado arquivos pela extensao - var global)
    CAMINHOS_GENOMAS=$(mktemp)
    find "$PASTA_GENOMAS" -type f -name "*.$EXTENSAO_GENOMA" > "$CAMINHOS_GENOMAS"
    if [ ! -s "$CAMINHOS_GENOMAS" ]; then
        log_error "Nenhum genoma com extensao $EXTENSAO_GENOMA encontrado em $PASTA_GENOMAS"
        return 1
    fi
    
    
    # =========== 1° ETAPA DE FILTRAGEM =====================
    # Ordenar, filtrar e renomear contigs
    
    log_info "Iniciando ordenacao e filtragem de contigs pequenos (<1000 pb)"

    # Loop 'while' para ler linha para processar cada genoma
    while IFS= read -r genoma || [ -n "$genoma" ]; do
        # Ignora linhas em branco 
        [ -z "$genoma" ] && continue

        # Remove eventuais espaços extras no início/fim da linha
        genoma=$(echo "$genoma" | xargs)

        # Verifica se o arquivo de genoma especificado na linha realmente existe
        if [ -f "$genoma" ]; then
        
            nome_base="$(basename "$genoma")"
            novo_arquivo="${DIR_SAIDA}/${nome_base}"

            # 1. 'seqkit sort -l -r': Ordena do maior para o menor contig
            seqkit sort --by-length --reverse "$genoma" 2> /dev/null | \
            # 2. 'seqkit seq -m 1000': Filtra mantendo contigs >= 1000 bp
            seqkit seq --min-len 1000 2> /dev/null| \
            # 3. 'seqkit replace --pattern ".*" --replacement 'Contig_{nr}: 
            # Reconhece o HEADER, e troca o nome por Contigs_nr (nr = var interna) (>"Contig_1, Contig_2, ...")
            seqkit replace --pattern ".*" --replacement 'Contig_{nr}' > "$novo_arquivo" 2> /dev/null
            
            # Verificando erro no seqkit
            if [ "$?" != 0 ]; then
                log_error "Comando seqkit falhou em genoma $genoma" >> "$LOG"
            fi
            
            # Guardando numero de contigs
            contigs_antes=$(grep -c "^>" "$genoma")
            contigs_depois=$(grep -c "^>" "$novo_arquivo")
            
            echo -e "${contigs_antes}\t${contigs_depois}" >> "$TABELA_NUMERO_CONTIGS"
            
        else
            echo "Aviso: O arquivo '$genoma' listado não foi encontrado. Pulando..." >> "$LOG"
        fi

    done < "$CAMINHOS_GENOMAS"

    log_info "Filtragem de contigs pequenos (<1000 pb) concluída para $(wc -l < "$CAMINHOS_GENOMAS") genoma(s)!"
    log_info "Os novos genomas foram salvos em '$DIR_SAIDA'."
    log_info "Arquivo com numero de contigs antes e depois da filtragem salvo em: $TABELA_NUMERO_CONTIGS"
    log_info "Possiveis erros na execucao salvos em: $LOG"
    
    log_info "\n\n"
    
    log_info "Iniciando remocao de montagens de baixa qualidade por:"
    log_info "N° de contigs max: $N_CONTIGS_MAX"
    log_info "N50 min: $N50_MIN"
    
    # ===============================================
    
    # =========== 2° ETAPA DE FILTRAGEM =====================
    # Remover genomas de acordo com estatisticas de qualidade
    
    # N° de contigs max. Default: 1000
    # N50 min (tamanho do menor contig necessario para completar 50% do genoma). Default: 5000 pb
    
    local ESTATISTICAS="estatisticas_qualidade_assembly.tsv"
    local LOW_QUALITY_DIR="${DIR_SAIDA}/{LOW_QUALITY_GENOMES}"
    criar_dir "$LOW_QUALITY_GENOMES"
    
    # 1. Criando arquivos com estatisticas dos genomas
    seqkit stats --tabular --all --infile-list "$CAMINHOS_GENOMAS" --threads "$NUMERO_CPU" > "$ESTATISTICAS"
    
    # Cabecalho de $ESTATISTICAS (trocando \t por ,):
    # file,format,type,num_seqs,sum_len,min_len,avg_len,max_len,Q1,Q2,Q3,sum_gap,N50,Q20(%),Q30(%),GC(%)
    
    LISTA_GENOMAS_BAIXA_QUAL=$(mktemp)
    LISTA_GENOMAS_ALTA_QUAL=$(mktemp)
    awk -F'\t' \
      -v max_contigs="$N_CONTIGS_MAX" \
      -v min_n50="N50_MIN"
      -v genomas_baixa_qual="$"
      -v genomas_alta_qual="$" '
	BEGIN {
	    OFS = "\t"
	}

	# 1. Mapeia o cabeçalho no primeiro registro
	NR == 1 {
	    for (i = 1; i <= NF; i++) {
		col[$i] = i
	    }
	    next
	}

	# 2. Processa as linhas de dados usando os nomes das colunas
	{
	    num_seqs = $(col["num_seqs"])
	    n50      = $(col["N50"])

	    # Aplica os critérios de filtragem
	    if (num_seqs > max_contigs || n50 < min_n50 ) {
		# Imprime o caminho/nome do arquivo REPROVADO na qualidade
		print $(col["file"]) > genomas_baixa_qual
	    }
	    
	    else
	       # Imprime o caminho/nome do arquivo APROVADO na qualidade
		print $(col["file"]) > genomas_alta_qual
	}' "$ESTATISTICAS"

    # =========== 3° ETAPA DE FILTRAGEM =====================
    # Calcular completude e contaminacao pelo checkm2 e filtrar
    
    # Completude min (n° de marcadores geneticos de copia unica presentes no genoma). Default: 75%
    # Contaminacao max (n° de marcadores geneticos replicados/redundantes no genoma). Default: 5%
    # Score = Completude - 5 * Contaminação
    
    # Verificando modulo do checkm2

}

# ==============================================================================
# Exemplo de Uso:
# ==============================================================================

# Executando a função passando o arquivo TXT contendo os caminhos:
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    # Variável global necessária para o find da função
    export EXTENSAO_GENOMA="fna"
    export NUMERO_CPU=4
    export N_CONTIGS_MAX=1000
    export N50_MIN=5000
    export COBERTURA_MIN=0
    log_info () { local MENSAGEM="${1?}" ; echo "$MENSAGEM" ; }
    log_error () { local MENSAGEM_ERRO="${1?}" ; echo "[ERRO] $MENSAGEM_ERRO" ; }
    criar_dir () { local DIR="${1?}" ; [ -d "$DIR" ] && rm -f "$DIR" ; mkdir -p "$DIR" ; }
    
    # Verificando dependencias 
    DEPENDENCIAS=( seqkit checkm2 )
    for cmd in "${DEPENDENCIAS[@]}"; do 
	if ! command -v "$cmd" &> /dev/null; then 
	    log_error "Comando nao encontrado: $cmd"
	    exit 1
	fi
    done
    
    # Executando funcao
    PASTA_GENOMA="/mnt/c/Users/jpcas/Downloads/BIOINFO/projects/prokfinder-github/ProkFinder/scripts/ncbi_dataset/data/GCF_050467545.1"
    filtrar_genomas_qualidade "$PASTA_GENOMA"
fi

# verificar_dependencias () { for cmd in "$DEPENDENCIAS"; do if ! command -v "$cmd" &> /dev/null ; then log_error "Comando nao encontrado: $cmd" ; fi ; done }
