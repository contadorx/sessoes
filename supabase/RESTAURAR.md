# O backup que volta

> **Este é o único critério de pronto do projeto que não se verifica lendo.**
> O doc 12 diz: *"o restore foi executado de verdade e a base restaurada abre.
> Prontuário perdido é fim do produto — este critério não se assina no papel."*
>
> Eu não consigo executar isto por você. Restaurar é uma operação no painel do
> Supabase, sobre infraestrutura real, e envolve criar um projeto e apagá-lo
> depois. O que eu consigo é deixar o roteiro e a prova — o script que diz, com
> uma resposta só, se a base restaurada está inteira ou não.

## Por que agora, e não depois do piloto

Hoje o banco tem dados de teste. Depois do piloto ele terá o prontuário de gente
real, e um restore que nunca foi testado é uma promessa que ninguém verificou —
exatamente o tipo de promessa que só se descobre falsa no pior dia possível.

Fazer o ensaio agora custa uma hora e um projeto temporário. Fazer depois custa
descobrir, no meio de um incidente, que o backup existia mas não voltava.

---

## O ensaio, em sete passos

**1. Confirme que o backup existe.**
No painel: `Database` → `Backups`. O plano pago faz backup diário e mantém PITR
(*point in time recovery*). Anote a hora do backup mais recente.

**2. Crie um projeto temporário** na mesma organização, na mesma região
(`sa-east-1`). Chame de `sessoes-ensaio`. Ele vai ser apagado no fim.

**3. Restaure o backup nele.**
No painel do projeto de produção, `Database` → `Backups` → `Restore to new
project`, apontando para o `sessoes-ensaio`. Se a sua versão do painel não
oferecer isso, o caminho equivalente é baixar o dump e restaurá-lo:

```bash
# no projeto de produção
supabase db dump --db-url "$URL_PRODUCAO" -f producao.sql

# no projeto de ensaio, numa base limpa
psql "$URL_ENSAIO" -f producao.sql
```

**4. Rode a prova.** No SQL Editor do `sessoes-ensaio`, cole
`supabase/verificar-restauracao.sql` e execute.

O script levanta exceção no primeiro furo e é silencioso quando passa. Ele
confere o que realmente importa depois de um restore, que não é "tem dado" e sim
**"as defesas voltaram junto"**:

- todas as tabelas existem e estão com RLS ligada;
- as políticas voltaram (uma tabela restaurada sem política é uma tabela aberta);
- as funções e os gatilhos voltaram — sem eles, a classificação de cancelamento,
  o retrato da mensagem e a cobrança automática simplesmente param de existir;
- os índices únicos que sustentam as invariantes voltaram;
- as extensões (`btree_gist`) voltaram — sem ela, duas pessoas na mesma hora
  deixa de ser impossível;
- as contagens batem com o que você anotou no passo 1.

**5. Abra o app apontado para a base restaurada.** Localmente, com
`NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` do `sessoes-ensaio`.
Entre, abra a agenda, abra uma ficha. **Restore que passa no script e não abre no
app não passou.**

**6. Rode as suítes adversariais** contra a base restaurada — as de
`supabase/tests/`. São elas que provam que o isolamento entre contas sobreviveu.
É a diferença entre "os dados voltaram" e "voltaram protegidos".

**7. Apague o `sessoes-ensaio`.** Ele contém uma cópia integral de dado sensível.
Enquanto existir, é uma segunda superfície de risco pela qual ninguém está
olhando.

---

## Anote o resultado

Depois do ensaio, registre em `claude/14-diario-de-bordo.md`:

- a data;
- quanto tempo levou do início do restore até o app abrir (é o seu RTO real, e
  ele vira o que você promete a uma cliente que perguntar);
- a idade do backup usado (é o seu RPO real — quanto de trabalho se perderia);
- o que falhou, se falhou.

Sem esses números, "temos backup" é uma frase, não um plano.

## Refazer

A cada mudança grande de esquema, e no mínimo **uma vez por trimestre**. Backup
não testado envelhece: o que voltava em março pode não voltar em setembro, e a
única forma de saber é tentar.
