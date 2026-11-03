/// Tasks that ran under the old "PiG engine" setting become .pig tasks; the setting is dropped.
enum Migration005_PigAgent {
    static let migration = Migration(
        version: 5,
        sql: """
        UPDATE tasks SET agent = 'pig'
            WHERE agent = 'pi' AND EXISTS (SELECT 1 FROM settings WHERE key = 'pi_engine' AND value = 'pig');
        UPDATE tasks SET previous_agent = 'pig'
            WHERE previous_agent = 'pi' AND EXISTS (SELECT 1 FROM settings WHERE key = 'pi_engine' AND value = 'pig');
        UPDATE projects SET default_agent = 'pig'
            WHERE default_agent = 'pi' AND EXISTS (SELECT 1 FROM settings WHERE key = 'pi_engine' AND value = 'pig');
        UPDATE settings SET value = 'pig'
            WHERE key = 'commit_message_agent' AND value = 'pi' AND EXISTS (SELECT 1 FROM settings WHERE key = 'pi_engine' AND value = 'pig');
        INSERT INTO settings (key, value) SELECT 'commit_message_agent', 'pig'
            WHERE NOT EXISTS (SELECT 1 FROM settings WHERE key = 'commit_message_agent')
            AND EXISTS (SELECT 1 FROM settings WHERE key = 'pi_engine' AND value = 'pig');
        UPDATE settings SET value = json_insert(value, '$[#]', 'pig')
            WHERE key = 'enabled_agents' AND json_valid(value) AND NOT EXISTS (SELECT 1 FROM json_each(settings.value) WHERE json_each.value = 'pig')
            AND EXISTS (SELECT 1 FROM settings s WHERE s.key = 'pi_engine' AND s.value = 'pig');
        UPDATE settings SET value = json_set(json_remove(value, '$.pi'), '$.pig', json_extract(value, '$.pi'))
            WHERE key = 'agent_executable_paths' AND json_valid(value) AND json_extract(value, '$.pi') IS NOT NULL;
        DELETE FROM settings WHERE key = 'pi_engine';
        """
    )
}
