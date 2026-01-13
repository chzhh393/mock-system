# 构建阶段
FROM docker.m.daocloud.io/library/maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /app

# 复制 Maven 配置（使用阿里云镜像）
COPY settings.xml /root/.m2/settings.xml

# 复制 pom.xml 并下载依赖（利用 Docker 缓存）
COPY pom.xml .
RUN mvn dependency:go-offline -B -s /root/.m2/settings.xml

# 复制源代码并构建
COPY src ./src
RUN mvn clean package -DskipTests -B -s /root/.m2/settings.xml

# 运行阶段
FROM docker.m.daocloud.io/library/eclipse-temurin:17-jre

WORKDIR /app

# 安装诊断工具
RUN apt-get update && apt-get install -y netcat-openbsd

# 从构建阶段复制 jar 文件
COPY --from=builder /app/target/*.jar app.jar

# 暴露端口
EXPOSE 8080

# 启动命令
ENTRYPOINT ["java", "-jar", "app.jar"]
