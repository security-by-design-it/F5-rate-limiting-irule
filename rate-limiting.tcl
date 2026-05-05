when RULE_INIT {
    # Maximaal aantal requests per IP per dag
    set static::max_requests 5000
 
    # URL waarop de rate limiting van toepassing is
    set static::rate_limit_uri "/api/uw-pad"
 
    # TTL in seconden (86400 = 1 dag)
    set static::window_seconds 86400
 
    # Naam van de data group voor whitelisting
    set static::whitelist_dg "ratelimit_ip_whitelist"
}
 
when HTTP_REQUEST {
    # Controleer of het verzoek de betreffende URL betreft
    if { [HTTP::uri] starts_with $static::rate_limit_uri } {
 
        set client_ip [IP::client_addr]
 
        # Controleer of het IP in de whitelist staat
        # class match werkt voor zowel exacte IP's als subnetten (bijv. 10.0.0.0/8)
        if { [class match $client_ip equals $static::whitelist_dg] } {
            # Whitelisted IP: geen rate limiting, direct doorsturen
            return
        }
 
        set today [clock format [clock seconds] -format "%Y%m%d"]
        set table_key "ratelimit_${client_ip}_${today}"
 
        # Teller ophogen (als sleutel niet bestaat begint table incr bij 1)
        set current_count [table incr $table_key]
 
        if { $current_count == 1 } {
            # Eerste request van dit IP vandaag: stel TTL in op 1 dag
            table replace $table_key $current_count $static::window_seconds $static::window_seconds
        }
 
        if { $current_count > $static::max_requests } {
            # Limiet bereikt: 429 Too Many Requests teruggeven
            HTTP::respond 429 content {
<html>
<head><title>429 Too Many Requests</title></head>
<body>
<h1>Too Many Requests</h1>
<p>You have exceeded the daily request limit of 5000 requests.</p>
<p>Please try again tomorrow.</p>
</body>
</html>
            } "Content-Type" "text/html" \
              "Retry-After" "86400" \
              "X-RateLimit-Limit" $static::max_requests \
              "X-RateLimit-Remaining" "0"
            return
        }
 
        # Informatieve headers meesturen naar de backend
        set remaining [expr { $static::max_requests - $current_count }]
        HTTP::header replace "X-RateLimit-Limit" $static::max_requests
        HTTP::header replace "X-RateLimit-Remaining" $remaining
    }
}
