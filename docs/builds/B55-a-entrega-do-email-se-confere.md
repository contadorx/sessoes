# B55 · A entrega do e-mail se confere · 3 dias · migração 0091

**Depende de credencial, e a ordem de implantação é parte da entrega.** Antes de
abrir, leia [`docs/canal/README.md`](../canal/README.md): ele diz o que do
repasse técnico se leva, o que colide com o que já existe, e o que fica
bloqueado por documento.

**A tese, e é a razão da build:** o provedor responde `success` quando a
mensagem entra **na fila dele**, não quando o destino recebe. A queda para um
segundo provedor cobre o servidor *recusar*; ela não cobre o caso que de fato
acontece — porta 25 bloqueada por volume, API respondendo `success`, mensagem
apodrecendo na fila. Falha silenciosa em e-mail transacional não quebra nada,
não aparece em log de erro, e o prejuízo é uma pasta do contador que ela jurou
ter mandado.

---

## Entrega

**1 · A confirmação entra em `mensagens`, e não numa tabela nova.** Migração
`0091`: `confirmada_em timestamptz`, os estados `perdida` e `reenviada` no
`check` de `mensagens.estado`, e o corpo guardado apenas para o que precisa ser
reenviado — com o prazo respondendo a `contas.retencao_anos`, não a uma
constante própria.

**`emails_saida` não entra.** `public.mensagens` já é o registro com
`chave_idem`, ciclo de vida e camada manual; uma segunda tabela respondendo "a
mensagem saiu?" é o antipadrão nº 1, e sobre mensagem que chega em paciente.

**2 · O webhook do provedor, com segredo, e a rota que recusa sem ele.**
`app/api/email/evento` traduz o evento do provedor para o estado da mensagem.
Sem `EMAIL_WEBHOOK_SEGREDO` a rota devolve 503 e **não grava** — o padrão é
fechado. Evento que não interessa responde 200 e é ignorado, para o provedor não
ficar retentando.

**3 · A varredura, na ordem em que as etapas são a regra.** Etapa 0 é a trava:
**sem nenhuma confirmação na janela, não se conclui perda de ninguém** — não
reenvia, não mexe no disjuntor, marca-se cega e grava-se o aviso. É a mesma
regra que a `0088` escreveu para a oferta sem mensagem.

**4 · O disjuntor fecha por evidência, nunca por tempo.** Abre quando a perda
passa do limite com amostra mínima; fecha só quando uma amostra recente não tem
perda nenhuma. O que a passagem do tempo autoriza é **sondar** — mandar uma
mensagem pelo caminho suspeito para que exista amostra.

**5 · O adaptador deixa de recusar, e só ele muda.**
`lib/mensageria/adaptadores.ts` passa a devolver o adaptador de e-mail quando as
variáveis existem. Nenhuma frase de tela é reescrita: desde a B50 todas derivam
de `envioAutomaticoLigado()` e de `adaptadorPara("email").disponivel`.

**6 · O estado cego dói.** Webhook mudo e cron parado são silêncios, e silêncio
não aparece sozinho: a data da última varredura é gravada a cada execução —
inclusive quando ela se declara cega — e passa a doer na tela de operação depois
de três ciclos.

---

## Pronto quando — verificado rodando

- [ ] um e-mail de teste sai e a linha em `mensagens` vira `entregue` **por
      webhook**, não por otimismo do cliente HTTP
- [ ] com o webhook desligado, a varredura se declara **cega**: não marca
      ninguém como perdido, não reenvia e não mexe no disjuntor
- [ ] mensagem aceita e sem confirmação além da janela vira `perdida`, e é
      reenviada **uma vez** pelo caminho de queda, com o mesmo corpo
- [ ] `falhou` (caixa inexistente) **não** é reenviada
- [ ] o disjuntor abre com perda acima do limite e **não fecha** com o tempo —
      só com amostra sem perda
- [ ] sem as variáveis do provedor, `adaptadorPara("email").disponivel` é
      `false` e nenhuma tela promete envio (a varredura da B50 já reprova isso)
- [ ] a suíte planta mensagem aceita e vencida **sem nenhuma confirmação na
      janela** e reprova qualquer reenvio
- [ ] `npm run verificar:colunas` continua limpo depois da migração

## Não entra

Tabela nova de saída de e-mail · segunda contagem de "a mensagem saiu?" ·
abertura e clique como métrica de produto (o documento avisa por que) ·
reenviar `falhou` · disjuntor que fecha no relógio · rota de teste sem segredo ·
**e-mail carregando dado clínico antes da cláusula do doc `18`**.

## As armadilhas

**Ligar o cron antes do webhook.** É o cenário da §6 do repasse: nada confirma,
tudo vira perdido, a base inteira é reenviada a cada 15 minutos, o disjuntor
abre e desliga o servidor que estava funcionando — sem uma linha de erro. A
ordem de implantação é entrega, não recomendação.

**Marcar como enviada para o número ficar bonito.** É o defeito que a B43 e a
B50 consertaram, e ele volta aqui com roupa nova: `success` do provedor não é
entrega.

**Guardar o corpo para sempre.** É documento de paciente parado no banco, e
webhook quebrado o transformaria em arquivo permanente de dado de terceiro.
