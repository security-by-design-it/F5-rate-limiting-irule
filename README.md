# F5 iRule — IP Rate Limiting per dag

Een F5 BIG-IP iRule die HTTP-verkeer beperkt tot **5000 requests per IP-adres per dag** op een specifieke URL, met ondersteuning voor IP-whitelisting via een data group.

---

## Inhoud

- [Functionaliteit](#functionaliteit)
- [Vereisten](#vereisten)
- [Installatie](#installatie)
- [Data group aanmaken](#data-group-aanmaken)
- [Configuratie](#configuratie)
- [HTTP Response headers](#http-response-headers)
- [Gedrag bij limietoverschrijding](#gedrag-bij-limietoverschrijding)
- [Bekende beperkingen](#bekende-beperkingen)

---

## Functionaliteit

- Rate limiting op basis van **IP-adres** en **dag** (reset elke dag om middernacht)
- Instelbare URL waarop de limiet van toepassing is
- IP-whitelisting via een externe **Address data group** (ondersteunt losse IP's én subnetten)
- Informatieve `X-RateLimit-*` response headers voor clients
- `429 Too Many Requests` response bij overschrijding, inclusief `Retry-After` header

---

## Vereisten

- F5 BIG-IP versie 11.x of hoger
- Toegang tot de BIG-IP GUI of TMSH
- Een bestaande Virtual Server waaraan de iRule gekoppeld kan worden

---

## Installatie

### Via de BIG-IP GUI

1. Ga naar **Local Traffic → iRules → iRule List**
2. Klik op **Create**
3. Geef de iRule een naam, bijvoorbeeld `irule_ratelimit_per_ip`
4. Plak de volledige iRule-code in het tekstveld
5. Klik op **Finished**
6. Ga naar je Virtual Server via **Local Traffic → Virtual Servers**
7. Open het tabblad **Resources**
8. Voeg de iRule toe onder **iRules** en klik op **Update**

### Via TMSH

```bash
# Maak de iRule aan
tmsh create ltm rule irule_ratelimit_per_ip {
    when RULE_INIT { ... }
    when HTTP_REQUEST { ... }
}

# Koppel de iRule aan een Virtual Server
tmsh modify ltm virtual <naam_virtual_server> rules add { irule_ratelimit_per_ip }

# Sla de configuratie op
tmsh save sys config
```

---

## Data group aanmaken

De iRule maakt gebruik van een Address data group voor IP-whitelisting. IP-adressen en subnetten in deze lijst worden **vrijgesteld** van rate limiting.

### Via de BIG-IP GUI

1. Ga naar **Local Traffic → iRules → Data Group List**
2. Klik op **Create**
3. Vul in:
   - **Name:** `ratelimit_ip_whitelist`
   - **Type:** `Address`
4. Voeg entries toe onder **Address Records**, bijvoorbeeld:

| Address | Omschrijving |
|---|---|
| `192.168.1.10` | Enkel IP-adres |
| `10.0.0.0/8` | Intern netwerk |
| `172.16.50.25` | Monitoring server |

5. Klik na elke entry op **Add**
6. Klik op **Finished**

### Via TMSH

```bash
tmsh create ltm data-group internal ratelimit_ip_whitelist \
    type ip \
    records {
        10.0.0.0/8 { }
        192.168.1.10/32 { }
        172.16.50.25/32 { }
    }

tmsh save sys config
```

> De data group kan live worden bijgewerkt zonder de iRule te herladen of verkeer te onderbreken.

---

## Configuratie

Alle instellingen staan bovenin de iRule in het `RULE_INIT` blok:

| Variable | Standaardwaarde | Omschrijving |
|---|---|---|
| `static::max_requests` | `5000` | Maximum aantal requests per IP per dag |
| `static::rate_limit_uri` | `/api/uw-pad` | URL-prefix waarop de limiet van toepassing is |
| `static::window_seconds` | `86400` | Tijdvenster in seconden (1 dag) |
| `static::whitelist_dg` | `ratelimit_ip_whitelist` | Naam van de whitelist data group |

### Voorbeeld: limiet aanpassen naar 1000 requests op `/api/v1/`

```tcl
when RULE_INIT {
    set static::max_requests 1000
    set static::rate_limit_uri "/api/v1/"
    set static::window_seconds 86400
    set static::whitelist_dg "ratelimit_ip_whitelist"
}
```

---

## HTTP Response headers

De iRule voegt de volgende headers toe aan elk doorgestuurd verzoek:

| Header | Omschrijving |
|---|---|
| `X-RateLimit-Limit` | Maximaal aantal toegestane requests per dag |
| `X-RateLimit-Remaining` | Resterend aantal requests voor dit IP vandaag |

Bij een `429` response worden aanvullend meegestuurd:

| Header | Waarde |
|---|---|
| `Retry-After` | `86400` (seconden tot reset) |
| `X-RateLimit-Remaining` | `0` |

---

## Gedrag bij limietoverschrijding

Wanneer een IP-adres de dagelijkse limiet overschrijdt, reageert de iRule direct met:

```
HTTP/1.1 429 Too Many Requests
Content-Type: text/html
Retry-After: 86400
X-RateLimit-Limit: 5000
X-RateLimit-Remaining: 0
```

Het verzoek wordt **niet** doorgestuurd naar de backend. De teller reset automatisch de volgende dag op basis van de datum in de tabelsleutel (`YYYYMMDD`).

---

## Bekende beperkingen

**Multi-blade omgevingen**
De F5 `table`-functie slaat data lokaal op per blade. In een chassis met meerdere blades kan een IP-adres per blade een eigen teller hebben, waardoor de effectieve limiet hoger uitvalt dan ingesteld. Overweeg in dat geval gebruik van een externe datastore via iCall of een sideband verbinding.

**Tijdzone**
De dagreset is gebaseerd op de systeemtijd van de BIG-IP. Controleer de tijdzoneconfiguratie via:

```bash
tmsh list sys ntp
date
```

**Subnetten in whitelist**
De data group gebruikt het type `Address`, waardoor zowel losse IP-adressen (`/32`) als subnetten (bijv. `10.0.0.0/8`) worden ondersteund. Zorg dat je bij losse IP-adressen expliciet `/32` opgeeft bij toevoeging via TMSH.
