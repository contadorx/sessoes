# A 0067b não está aqui, e este arquivo existe para isso doer

O P8 foi aplicado no Supabase em 02/09 em duas migrações, `0067` e `0067b`, e
**nenhuma das duas chegou ao repositório** — a lei 5 violada em silêncio por
quatro dias. A `0067` foi recuperada em 03/09 e está ao lado deste arquivo,
conferida por md5 contra o banco. A `0067b` continua faltando.

## O que ela faz

Reescreve as **oito funções** que citavam os identificadores que a `0067`
renomeou (`emitido_em` → `marcado_por_ela_em`, `numero_rfb` →
`numero_informado`, estado `'emitido'` → `'marcado_por_ela'`):

`ao_pagar_gera_recibo_rfb` · `desmarcar_recibo_rfb` · `dias_para_desfazer` ·
`exportar_conta` · `fechar_mes_da_conta` · `marcar_recibo_rfb` ·
`recalcular_eixos` · `receita_saude_do_ano`.

Ela é o exemplo vivo da lei 6: **cada corpo foi lido do banco**
(`pg_get_functiondef`), não da migração que criou a função — e o cabeçalho dela
diz por quê, citando a 0060 (que apagou o `insert` da trilha) e a 0060d (que
perdeu o `enfileirar_mensagem`). `exportar_conta` entra lá **sem uma linha
alterada**, de propósito, para ficar registrado que foi olhada e absolvida em
vez de esquecida.

## Como recuperar, byte a byte

O corpo está guardado no próprio banco. Com a string de conexão do projeto:

```bash
psql "$DB_URL" -Atq \
  -c "select statements[1] from supabase_migrations.schema_migrations
       where name = 'as_oito_funcoes_que_falavam_a_palavra_antiga'" \
  > supabase/migrations/0067b_as_oito_funcoes_que_falavam_a_palavra_antiga.sql
```

E **confira antes de commitar** — o arquivo só vale se for idêntico ao que
rodou:

```bash
md5sum supabase/migrations/0067b_as_oito_funcoes_que_falavam_a_palavra_antiga.sql
# tem de dar exatamente:
# 9242187d0f9b4c16a4a8bfc763ff01bc
```

São 30.733 caracteres em 718 linhas. Se o md5 não bater, **não commite**: um
arquivo 99,9% certo é pior do que arquivo nenhum, porque o repositório passa a
afirmar que guarda a migração que rodou. Foi o que aconteceu na primeira
tentativa de recuperar a `0067` — catorze réguas de comentário com um traço a
mais, e o md5 foi a única coisa que percebeu.

Apague este arquivo quando o md5 fechar.
