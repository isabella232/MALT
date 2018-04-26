#!/bin/bash

curl -s -H "Content-Type: application/json" -XPOST http://admin:admin@$(triton ip $1):3000/api/datasources -d "{
\"name\": \"prometheus\",
\"type\": \"prometheus\",
\"access\": \"direct\",
\"url\": \"$2\"}" > /dev/null 2>&1
