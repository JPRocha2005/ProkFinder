# Criar estrutura de diretorios para guardar genomas e metadados de acordo com a taxonomia

# Chamada da funcao
# create_taxonomic_dir_structure <taxonomy_file> <taxonomic_dir_struct_name> <pasta_genomas> <extensao_genoma>

create_taxonomic_dir_structure () {
        local ARQUIVO_TAXONOMIA="${1?}"
        local OUTPUT_DIR_TAXONOMY="${2?}"
        local PASTA_GENOMAS="${3?}"
        local EXTENSAO_GENOMA="${4?}"
        
        # Limpar diretorio e gerar novo
        limpar_diretorio "$OUTPUT_DIR_TAXONOMY"
        
        # Formato arquivo de taxonomia
        # GCA_000236605.1 d__Bacteria;p__Bacillota;c__Bacilli;o__Bacillales;f__Anoxybacillaceae;g__Geobacillus;s__Geobacillus thermoleovorans

        # Reformar arquivo de taxonomia 
        # trocar ; por \t
        # trocar ' ' por '_' )
        local TEMP_TAXONOMY=$(mktemp)
        tail -n +2 "$ARQUIVO_TAXONOMIA" | tr ';' '\t' | tr ' ' '_' > "$TEMP_TAXONOMY"
        
        # Criar lista com os nomes dos arquivos dos genomas no dir de genomas
        local LISTA_CAMINHO_GENOMAS=$(mktemp)
        encontrar_caminho_genoma "$LISTA_CAMINHO_GENOMAS" || return 1
        
        awk -F'\t' -v dir_taxonomico="$OUTPUT_DIR_TAXONOMY" '
                NR == FNR {  # 1° Arquivo - Lista do caminho dos genomas
                
                        # Guardar o caminho do arquivo do genoma
                        caminho_genoma = $0
                        
                        # Encontrar o id do genoma (\\. vira \. apos atribuicao)
                        REGEX_ID_GENOMA = "GC[AF]_[0-9]+\\.[0-9]+"
                        if (match($0, REGEX_ID_GENOMA)) {
                                id_genoma = substr($0, RSTART, RLENGTH) 
                        }
                        
                        # Guardar indice e caminho em um vetor
                        vetor_caminhos[id_genoma] = caminho_genoma
                        
                        # Pular a linha
                        next
                
                }   
                
                FNR >= 1 { # 2° Arquivo - Taxonomia dos genomas
                        
                        # Guardar o acesso do genomas
                        acesso_genoma = $1
                        
                        # Guardar os taxons em variaveis
                        domain = $2
                        phylum = $3
                        class = $4
                        order = $5
                        family = $6
                        genus = $7
                        species = $8
                        
                        # Montar arrays de prefixos e ranks (indices 1..7)
                        split("d__ p__ c__ o__ f__ g__ s__", vetor_prefixos, " ")
                        vetor_ranks[1] = domain
                        vetor_ranks[2] = phylum
                        vetor_ranks[3] = class
                        vetor_ranks[4] = order
                        vetor_ranks[5] = family
                        vetor_ranks[6] = genus
                        vetor_ranks[7] = species
                        
                        # Zerar ranks que estao vazios (rank igual apenas ao prefixo, ex: "s__")
                        for (i = 1; i <= 7; i++) {
                                if (vetor_ranks[i] == vetor_prefixos[i]) {
                                        vetor_ranks[i] = ""
                                }
                        }
                        
                        # Montar caminho considerando apenas ranks nao vazios
                        novo_caminho = dir_taxonomico "/"
                        for (i = 1; i <= 7; i++) {
                                if (vetor_ranks[i] != "") {
                                        novo_caminho = novo_caminho vetor_ranks[i] "/"
                                }
                        }
                        
                        # Criar diretorios
                        if (system("mkdir -p " novo_caminho) != 0) {
                                print "[ERRO] Criacao do diretorio para a linhagem (" novo_caminho ") falhou";
                                exit 1;
                        }
                        
                        # Encontrar o caminho do genoma correspondente no vetor
                        if (acesso_genoma in vetor_caminhos) {
                                
                                caminho_genoma = vetor_caminhos[acesso_genoma]
                                
                                if (system("cp " caminho_genoma " " novo_caminho) != 0) {
                                        print "[ERRO] Mover o genoma (" caminho_genoma ") para novo diretorio (" novo_caminho ") falhou";
                                        exit 1;
                                } 
                        }
                }
        
        ' "$LISTA_CAMINHO_GENOMAS" "$TEMP_TAXONOMY" \
                || { echo "[ERRO] Comando awk falhou na funcao ${FUNCNAME[0]}" ; return 1 ; }
                
        echo "[INFO] Estrutura diretorio para $TAXON_ANALISADO criada!" >> "$LOG_FILE"
   
   # Limpar arquivos temporarios
   rm -f "$TEMP_TAXONOMY" "$LISTA_CAMINHO_GENOMAS"
}

# Funcao para listar o caminho completo dos diretorios das diferentes especies
# para serem utilizadas na filtragem por mge e desreplicacao (dir-folha precisa ter 2 ou mais genomas)

# Uso: <estrutura_dir_tax> <tabela_dir_folha>
listar_dir_folha () {
        local DIR_TAXONOMY="${1?}"
        local ARQ_DIR_FOLHA="${2?}"

        # 1. Encontra todos os diretorios
        # 2. Ordena em ordem reversa para os diretorios filhos (a/b/c) virem antes dos pais (a/b/)
        # 3. Identifica os diretorios sem diretorios filho (diretorios-folha)
        # 4. Guarda os dir-folha na lista
        find "$DIR_TAXONOMY" -type d | \
        sort -r | \
        awk -v tabela_dir_folha="$ARQ_DIR_FOLHA" '
                {
                caminho_dir = $0

                # Se o caminho anterior (p) NAO comecar com o caminho atual (caminho_dir) seguido de "/",
                # entao caminho_dir é um diretorio-folha (nao tem filhos)
                if (index(p, caminho_dir "/") != 1) {
                        comando = "find \"" caminho_dir "\" -maxdepth 1 -type f | wc -l"
                        comando | getline num_genomas
                        close(comando)  # fecha o canal para nao estourar o limite de arquivos abertos

                        # Guarda o dir-folha da especie e o numero de genomas
                          print caminho_dir "\t" num_genomas > tabela_dir_folha
                }

                p = caminho_dir  # guarda o caminho atual para a proxima iteracao
                }
        '
}