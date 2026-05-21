# ENV2YAML

Convert `.env` variables into Kubernetes YAML instantly in the browser.

## 📸 Screenshot

![ENV2YAML Screenshot](https://raw.githubusercontent.com/virsuryaircas/env2yaml/main/en2yaml-web-screenshot.png)

Generate:
- ConfigMap YAML
- Secret YAML


## ✨ Features

- Pure frontend tool
- Runs completely in browser
- Nothing sent to any server
- Kubernetes ready output
- Save time

## ⚙️ Live Tool

https://virsuryaircas.github.io/env2yaml/

## Example

### 👉 Input
```env
APP_NAME=my-awesome-app
APP_ENV=production
APP_PORT=8080
DEBUG=false
```

### ✅ Output
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-config
  namespace: production
data:
  APP_NAME: "my-awesome-app"
  APP_ENV: production
  APP_PORT: "8080"
  DEBUG: "false"
```
## 📟 Checkout branch CLI

https://github.com/virsuryaircas/env2yaml/tree/cli
