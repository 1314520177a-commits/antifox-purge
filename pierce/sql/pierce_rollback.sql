-- ============================================================
-- antifox-pierce 回滚（离线路径）
-- 执行：psql "$ANTIFOX_PG_DSN" -f pierce_rollback.sql
-- 注意：顺序不能反 —— 先把 current_prompt_id 从 PIERCE 版本移开，
--       否则删 agent_prompts 会撞 fk_agents_curprompt 外键。
-- ============================================================
BEGIN;

-- ---- 1) 指针退回最近一条非 PIERCE 版本 ----
UPDATE agents a
SET current_prompt_id = (
        SELECT p.id
        FROM agent_prompts p
        WHERE p.agent_id = a.id
          AND COALESCE(p.note, '') <> 'pierce v1 常驻协议注入'
        ORDER BY p.version DESC
        LIMIT 1
    ),
    updated_at = now()
WHERE EXISTS (
        SELECT 1 FROM agent_prompts p
        WHERE p.id = a.current_prompt_id
          AND p.note = 'pierce v1 常驻协议注入'
    );

-- ---- 2) 删除 PIERCE 版本 ----
DELETE FROM agent_prompts WHERE note = 'pierce v1 常驻协议注入';

-- ---- 3) 关闭 skill 可见性（skill 目录文件保留，可再开）----
DELETE FROM agent_skill_visibility
WHERE skill_name IN ('pierce-core', 'pierce-chain');

COMMIT;

-- 校验：current_prompt_note 不应再出现 pierce v1
SELECT a.key,
       (SELECT count(*) FROM agent_skill_visibility v
         WHERE v.agent_id = a.id
           AND v.skill_name IN ('pierce-core','pierce-chain'))                AS pierce_skills,
       (SELECT note FROM agent_prompts p WHERE p.id = a.current_prompt_id)     AS current_prompt_note
FROM agents a
ORDER BY a.key;
