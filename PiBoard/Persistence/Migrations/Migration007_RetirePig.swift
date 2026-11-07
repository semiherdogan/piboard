/// PiG is no longer an agent. Its sessions live under ~/.pi/agent like Pi's, so its tasks resume as Pi.
enum Migration007_RetirePig {
    static let migration = Migration(
        version: 7,
        sql: """
        UPDATE tasks SET agent = 'pi' WHERE agent = 'pig';
        UPDATE tasks SET previous_agent = 'pi' WHERE previous_agent = 'pig';
        UPDATE projects SET default_agent = 'pi' WHERE default_agent = 'pig';
        UPDATE settings SET value = 'pi' WHERE key = 'commit_message_agent' AND value = 'pig';
        UPDATE settings SET value = COALESCE(
                (SELECT json_group_array(json_each.value) FROM json_each(settings.value) WHERE json_each.value <> 'pig'
                 HAVING COUNT(*) > 0),
                '["pi"]')
            WHERE key = 'enabled_agents' AND json_valid(value)
            AND EXISTS (SELECT 1 FROM json_each(settings.value) WHERE json_each.value = 'pig');
        UPDATE settings SET value = json_remove(value, '$.pig')
            WHERE key = 'agent_executable_paths' AND json_valid(value);
        """
    )
}
