# As capturas de tela da landing

Esta pasta está vazia de propósito. Ela é o único lugar da página que **eu não
consigo preencher daqui**, e este arquivo explica por quê, o que fazer, e o que
não pode aparecer nas imagens.

## Por que não fiz as capturas

O ambiente onde eu trabalho bloqueia `supabase.co` no proxy de saída. O
navegador e o servidor Next que eu subo aqui não conseguem falar com o banco —
só as ferramentas MCP conseguem, e elas executam SQL, não abrem tela. Eu criei
a conta de demonstração, semeei os pacientes e as sessões, subi o aplicativo na
porta 3200 e tentei entrar pelo Playwright; a resposta foi
`ERR_TUNNEL_CONNECTION_FAILED` na chamada de autenticação.

Preferi deixar a pasta vazia a inventar mais um desenho. A auditoria pediu
prova de que existe software; um diagrama a mais não responde essa pergunta.

## A conta de demonstração

Já existe no banco, já está marcada como conta de teste (sai das métricas do
painel e continua na lista):

- **e-mail:** demo@sessoes.com.br
- **senha:** DemoSessoes!2026

Tem oito pacientes cadastrados por iniciais e oito sessões espalhadas pela
semana, em estados diferentes — atendida e paga, atendida a receber, prevista,
falta com aviso — para que a agenda apareça com cores e não vazia.

## O que capturar

Rode o aplicativo (`npm run dev`) na sua máquina, entre com a conta acima e
salve três arquivos **nesta pasta**, com estes nomes exatos:

| arquivo            | tela                | o que precisa estar visível                          |
|--------------------|---------------------|------------------------------------------------------|
| `agenda.png`       | `/agenda`           | a semana inteira, com horários em estados diferentes |
| `sessao.png`       | uma sessão aberta   | o painel da sessão com cobrança e pagamento          |
| `recebimentos.png` | `/recebimentos`     | a lista de divergências, não uma lista vazia         |

Capture em janela de **1280 × 800**, tema claro, sem a barra do navegador.

## O que a seção faz com eles

A seção **"Veja o Sessões funcionando"** aparece sozinha na landing, entre
"Você registra a sessão uma vez" e "O registro do mês". Ela é condicional: o
servidor confere quais destes arquivos existem e monta a seção com os que
encontrar. Nenhum arquivo, nenhuma seção — a página não fica com um buraco nem
com uma promessa vazia. Um arquivo só, a seção nasce com um.

A leitura acontece no build. Trocar uma captura pede um deploy novo, o que é
correto: a imagem faz parte do que a página afirma.

## O aviso que importa

**Nenhum nome de paciente pode aparecer.** A conta foi semeada com iniciais
justamente por isso, mas confira a imagem antes de salvar — um nome inteiro num
canto de tela, numa landing que promete sigilo, seria o vazamento que a própria
página diz que não acontece. Confira também que não aparece número de telefone,
CPF nem valor de sessão associado a uma pessoa identificável.
